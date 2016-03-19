
class = require 'middleclass'

local SQL = class( 'SQL' )


SQL.verb = ''
SQL.columns = {}
SQL.tables = {}
SQL.conditions = {}
SQL.options = { name_quote = '`' }


function SQL:initialize( verb, options )
  self.verb = verb
end


function SQL.static:SELECT( columns, options )
  return SQL:new( 'SELECT', options ):SELECT( columns )
end


function SQL.static:UPDATE( columns, options )
  return SQL:new( 'UPDATE', options ):SELECT( columns )
end


function SQL.static:DELETE( columns, options )
  return SQL:new( 'DELETE', options ):SELECT( columns )
end


function SQL.static:validate_and_quote_name( name )
  if name:match( '[^%w_%.]+' ) then
    error( "name may contain alphanumeric characters with underscores. '" .. name .. "' invalid." )
  end
  return self.options.name_quote .. name .. self.options.name_quote
end


function SQL.static:validate_and_upcase_relation( relation )
  if relation:match( '[^<>=]+' ) and relation:upper() ~= 'IN' and relation:upper() ~= 'NOT IN' and relation:upper() ~= 'IS' then
    error( "relation may be '<', '>', '=', 'IN', 'NOT IN', 'IS'. '" .. relation .. "' invalid." )
  end

  return relation:upper()
end


function SQL.static:single_quote_and_escape_value( value )
  if type( value ) == 'string' then
    value = "'" .. value:gsub( "'", "''" ) .. "'"
  end
  return value
end


function SQL:SELECT( columns )

  for alias, name in pairs( columns ) do

    name = SQL:validate_and_quote_name( name )

	if type( alias ) == 'number' then
	  alias = name
	else
	  alias = SQL:validate_and_quote_name( alias )
	end

	self.columns[alias] = name
  end

  return self
end


function SQL:FROM( tables )

  for alias, name in pairs( tables ) do

	name = SQL:validate_and_quote_name( name )

	if type( alias ) == 'number' then
	  alias = name
	else
	  alias = SQL:validate_and_quote_name( alias )
	end
	self.tables[alias] = name
  end

  return self

end


function SQL:OR_WHERE( conditions )

  if type( conditions ) == 'table' and type ( conditions[1] ) == 'string' then
    conditions = { OR = true, conditions }
  else
    conditions['OR'] = true
  end

  return SQL.WHERE( self, conditions )
end


function SQL:WHERE( conditions )

  if type( conditions ) == 'table' and type ( conditions[1] ) == 'string' then
    conditions = { ['conjunction'] = 'AND', conditions }
  end

  local _recurse_where
  _recurse_where = function ( wheres )

    local conjunction = 'AND'
    -- AND is default but if OR is specified then it is used
    if wheres['OR'] then conjunction = 'OR' end

	local where_level_conditions = { ['conjunction'] = conjunction }

    for index, clause in ipairs( wheres ) do

      local name, relation, value = unpack( clause )

	  -- if first item is a table recurse
	  if type( name ) == 'table' then
        table.insert( where_level_conditions, _recurse_where( clause ) )

	  else
	    name = SQL:validate_and_quote_name( name )

		relation = SQL:validate_and_upcase_relation( relation )

		if type( value ) == 'string' then
		  if relation == 'IS' then
			if value:upper() == 'NULL' or value:upper() == 'NOT NULL' then
			  value = value:upper()
			else
		      error( "value may be 'NULL', 'NOT NULL'. '" .. value .. "' invalid." )
			end
		  else
		    value = SQL:single_quote_and_escape_value( value )
		  end

		elseif type( value ) == 'boolean' then
		  if value then value = 'TRUE' else value = 'FALSE' end

		elseif type( value ) == 'table' and ( relation == 'IN' or relation == 'NOT IN' ) then
          local new_value = '( '
		  for _, val in ipairs( value ) do
		    if type( val ) == 'string' then
			  val = SQL:single_quote_and_escape_value( val )
			elseif type( val ) == 'boolean' then
		      if val then val = 'TRUE' else val = 'FALSE' end
			end
			new_value = new_value .. val .. ', '
		  end
		  value = new_value:sub( 1, -3 ) .. ' )'

		end

		table.insert( where_level_conditions, { name, relation, value } )

	  end

    end

	return where_level_conditions

  end

  -- determine how yo merge conditions with existing ones
  if #self.conditions == 0 then
	self.conditions = _recurse_where( conditions )
  else

    if ( conditions['OR'] and self.conditions['conjunction'] == 'OR' ) or
	  ( conditions['AND'] and self.conditions['conjunction'] == 'AND' ) then
      local more_conditions = _recurse_where( conditions )

	  for _, condition in ipairs( more_conditions ) do
	    table.insert( self.conditions, condition )
	  end
	else
	  local previous_conditions = self.conditions
	  self.conditions = _recurse_where( conditions )
	  table.insert( self.conditions, previous_conditions )
	end
  end


  return self

end


function SQL:__tostring() return SQL.statement( self ) end
function SQL:statement()

  local statement = "SELECT"

  for alias, name in pairs( self.columns ) do
    if alias ~= name then
      statement = statement .. "\n  " .. name .. ' AS ' .. alias .. ','
	else
	  statement = statement .. "\n  " .. name .. ','
	end
  end

  statement = statement:sub( 1, -2 ) .. "\nFROM"


  for alias, name in pairs( self.tables ) do
    if alias ~= name then
      statement = statement .. "\n  " .. name .. ' ' .. alias .. ','
	else
	  statement = statement .. "\n  " .. name .. ','
	end
  end

  statement = statement:sub( 1, -2 ) .. "\nWHERE"

  local _recurse_conditions
  _recurse_conditions = function( conditions, indent )

    local where_statement = ''
	local conjunction = conditions['conjunction']

	for _, condition in ipairs( conditions ) do

	  local name, relation, value = unpack( condition )

	  if type( name ) == 'table' then
		where_statement = where_statement .. ' (' .. _recurse_conditions( condition, indent + 2 )
		  .. "\n" .. (' '):rep( indent + 2) .. ') ' .. conjunction
	  else
	    where_statement = where_statement .. "\n  " .. (' '):rep( indent ) .. name .. ' ' .. relation .. ' ' .. value .. ' ' .. conjunction
	  end
	end

    return where_statement:sub( 1, -conjunction:len() - 1 )
  end

  statement = statement .. _recurse_conditions( self.conditions, 0 )

  return statement
end


return SQL

--[=[

Example usage:

query = SQL
  :SELECT {
    ['id'] = 'u_id',
    ['firstname'] = 'u_firstname',
    ['lastname'] = 'u_lastname',
	'u_email'
  }
  :FROM {
    ['u'] = 'user',
	'person'
  }
  :WHERE{
    AND = true,   -- <=== default
	{ 'u.id', '=', 12 },
	{ 'train', '=', 'due' },
	{ 'sheep', 'IN', { 9, 78, 78, 90 } },
	{ 'cows', 'NOT IN', { 'coats', 'pyjamas' } },
	{ 'beep', 'IS', 'NULL' }
  }
  --[[
	{ 'lastname', '>=', "Davidson's" },
	{
	  OR = true,  -- <=== override
	  { '1one', '=', 1 },
	  { '2two', '=', 2 }
	},
	{
	  OR = true,
	  { '1..', '=', 1 },
	  { '2..', '=', 2 },
	  {
	    { 'fgh', '>', 7},
		{ 'kjh', '<=', 12 }
	  }
	},
	{ 'shoe', '=', 'fits' }
  }
  :IN {
	'email', { 1, 2, 3, 4, 5 }
  }
  :NOT_IN {
	'email', { 7, 8 }
  }
  --]]

print( query )

query:OR_WHERE{
  { 'book', '=', 7 },
  { 'goons', '=', 'everywhere' }
}

query:OR_WHERE{
  { 'eee', 'IS', 'NULL' }
}

print( query )


--]=]
