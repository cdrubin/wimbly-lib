
class = require 'middleclass'

inspect = require 'inspect'


local SQL = class( 'SQL' )


SQL.options = { name_quote = '`' }


function SQL:initialize( verb )
  self.verb = verb
end


function SQL.static:SELECT( columns )
  local sql = SQL:new( 'SELECT' )
  sql.tables = {}
  sql.columns = {}
  self.conditions = {}
  sql.SET = false
  return sql:SELECT( columns )
end


function SQL.static:SELECT_DISTINCT( columns )
  local sql = SQL:new( 'SELECT DISTINCT' )
  sql.tables = {}
  sql.columns = {}
  self.conditions = {}
  sql.SET = false
  return sql:SELECT( columns )
end


function SQL.static:UPDATE( tablename )
  local sql = SQL:new( 'UPDATE' )
  sql.table = ''
  sql.values = {}
  self.conditions = {}
  sql.FROM = false
  return sql:UPDATE( tablename )
end


function SQL.static:INSERT( tablename, rows )
  local sql = SQL:new( 'INSERT INTO' )
  sql.table = ''
  sql.rows = {}
  sql.FROM = false
  sql.SET = false
  sql.WHERE = false
  sql.OR_WHERE = false
  return sql:INSERT( tablename, rows )
end


function SQL.static:DELETE( tablename )
  local sql = SQL:new( 'DELETE FROM' )
  sql.table = ''
  self.conditions = {}
  sql.FROM = false
  sql.SET = false
  return sql:DELETE( tablename )
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
    -- don't quote NULL, TRUE or FALSE
    if value ~= 'NULL' and value ~= 'TRUE' and value ~= 'FALSE' then
      value = "'" .. value:gsub( "'", "''" ) .. "'"
    end
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


function SQL:UPDATE( tablename )

  self.table = SQL:validate_and_quote_name( tablename )

  return self
end


function SQL:SET( values )

  for name, value in pairs( values ) do

    name = SQL:validate_and_quote_name( name )
    value = SQL:single_quote_and_escape_value( value )

    self.values[name] = value
  end

  return self
end


function SQL:INSERT( tablename, rows )

  self.table = SQL:validate_and_quote_name( tablename )

  if type( rows ) == 'table' and type ( next( rows ) ) == 'string' then
    rows = { rows }
  end

  local names = {}
  for name, value in pairs( rows[1] ) do
    table.insert( names, name )
  end

  self.table = self.table .. "\n  ( "

  for _, name in ipairs( names ) do
    self.table = self.table .. SQL:validate_and_quote_name( name ) .. ', '
  end
  self.table = self.table:sub( 1, -3 ) .. ' )'

  for _, row in ipairs( rows ) do

    local processed_row = {}
    for _, name in ipairs( names ) do
      table.insert( processed_row, SQL:single_quote_and_escape_value( row[ name ] ) )
    end

    table.insert( self.rows, processed_row )
  end

  return self
end


function SQL:DELETE( tablename )

  self.table = SQL:validate_and_quote_name( tablename )

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

  local statement = self.verb .. ' '


  if self.columns then
	for alias, name in pairs( self.columns ) do
	  if alias ~= name then
		statement = statement .. "\n  " .. name .. ' AS ' .. alias .. ','
	  else
		statement = statement .. "\n  " .. name .. ','
	  end
	end
  end


  if self.table then
	statement = statement .. "\n  " .. self.table .. ' '
  elseif self.tables then
	statement = statement:sub( 1, -2 ) .. "\nFROM"

	for alias, name in pairs( self.tables ) do
	  if alias ~= name then
		statement = statement .. "\n  " .. name .. ' ' .. alias .. ','
	  else
		statement = statement .. "\n  " .. name .. ','
	  end
	end
  end


  if self.rows then
	statement = statement:sub( 1, -2 ) .. "\nVALUES"

	for _, row in ipairs( self.rows ) do
      statement = statement .. "\n  ( "
      for _, column in ipairs( row ) do
        statement = statement .. column .. ', '
      end
      statement = statement:sub( 1, -3 ) .. ' ), '
    end

    statement = statement:sub( 1, -3 )
  end


  if self.values then
    statement = statement:sub( 1, -2 ) .. "\nSET"

    for name, value in pairs( self.values ) do
  	statement = statement .. "\n  " .. name .. ' = ' .. value .. ','
    end
  end


  if #self.conditions > 0 then
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
  end

  return statement
end



---[=[

--Example usage:

--SQL.options.name_quote = '|'

local query = SQL
  :SELECT {
    ['id'] = 'u_id',
    ['firstname'] = 'u_firstname',
    ['lastname'] = 'u_lastname',
	'u_email',
    'age',
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

print()

query = SQL
  :UPDATE( 'user' )
  :SET{
    ['id'] = 7,
    ['firstname'] = firstname,
    ['lastname'] = lastname,
	['column'] = 'NULL'
  }
  :WHERE{
    AND = true,   -- <=== default
	{ 'u.id', '=', 12 },
	{ 'train', '=', 'due' },
	{ 'sheep', 'IN', { 9, 78, 78, 90 } }
  }

print( query )

print()

query = SQL
  :INSERT( 'user', {
    { ['email'] = 'TRUE', ['firstname'] = 'moo', ['surname'] = 'loo' },
    { ['email'] = 'moo2@here.com', ['firstname'] = 'moo2', ['surname'] = 'loo2' }
  } )

print( query )


query = SQL
  :INSERT( 'user', {
    ['email'] = 'moo@here.com',
    ['firstname'] = 'NULL',
    ['surname'] = 'TRUE'
  } )

print( query )
print()

query = SQL
  :DELETE( 'user' )
  :WHERE{
    AND = true,   -- <=== default
	{ 'u.id', '=', 12 },
	{ 'train', '=', 'due' },
	{ 'sheep', 'IN', { 9, 78, 78, 90 } }
  }


print( query )

--]=]


return SQL
