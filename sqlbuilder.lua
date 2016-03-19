
class = require 'middleclass'

local SQL = class( 'SQL' )

SQL.verb = ''
SQL.columns = {}
SQL.tables = {}
SQL.conditions = {}


function SQL:initialize( verb )
  self.verb = verb
end


function SQL.static:SELECT( columns )
  return SQL:new( 'select' ):SELECT( columns )
end


function SQL.static:validate_and_transform_name( name )
  if name:match( '[^%w_]+' ) then
    error( "name may contain alphanumeric characters with underscores. '" .. name .. "' invalid." )
  end
end


function SQL:SELECT( columns )

  for alias, name in pairs( columns ) do

	if name:match( '[^%w_]+' ) then
      error( "name may contain alphanumeric characters with underscores. '" .. name .. "' invalid." )
	end

	if type( alias ) == 'number' then
	  alias = name
	else
	  if alias:match( '[^%w_]+' ) then
        error( "alias may contain alphanumeric characters with underscores. '" .. alias .. "' invalid." )
	  end
	end

	self.columns[alias] = name
  end

  return self
end


function SQL:FROM( tables )

  for alias, name in pairs( tables ) do
    if type( alias ) == 'number' then alias = name end
	self.tables[alias] = name
  end

  return self

end


function SQL:WHERE( conditions )

  local _recurse_where
  _recurse_where = function ( wheres )

    local conjunction = 'AND'
    -- AND is default but if OR is specified then it is used
    if wheres['OR'] then conjunction = 'OR' end

	local where_level_conditions = {}
	where_level_conditions['conjunction'] = conjunction

    for index, clause in ipairs( wheres ) do

      local name, relation, value = unpack( clause )

	  -- if first item is a table recurse
	  if type( name ) == 'table' then
        table.insert( where_level_conditions, _recurse_where( clause ) )

	  else
		if name:match( '[^%w_%.]+' ) then
		  error( "name may contain alphanumeric characters with underscores. '" .. name .. "' invalid." )
		end

		if relation:match( '[^<>=]+' ) then
		  error( "relation may be '<', '>', '='. '" .. relation .. "' invalid." )
		end

		if type( value ) == 'string' then
		  -- 'escape' quotes in value
		  value = value:gsub( "'", "''" )
		  value = "'" .. value .. "'"
		end

		table.insert( where_level_conditions, { name, relation, value } )

	  end

    end

	return where_level_conditions

  end

  if #self.conditions == 0 then
	self.conditions = _recurse_where( conditions )
    --table.insert( self.conditions, where_conditions )
  else

    -- table merge if conjunction same or error!
  end
  --table.insert( self.conditions, _recurse_where( conditions ) )


  return self

end


function SQL:IN( name, values )
  return self
end


function SQL:NOT_IN( name, values )
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


--return SQL
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

local inspect = require( 'inspect' )

print( query )

-- return SQL

