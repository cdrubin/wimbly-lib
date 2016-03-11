
class = require 'middleclass'

local SQL = class( 'SQL' )

function SQL:__tostring()
  -- call statement or vice-versa
  return SQL:statement()
end

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
    --print( '-n-' .. type( name ) )
	--print( '+a+' .. type( alias ) )

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


function SQL:WHERE( conditions ) return SQL:AND_WHERE( conditions ) end
function SQL:AND( conditions ) return SQL:AND_WHERE( conditions ) end
function SQL:AND_WHERE( conditions )

  for _, clause in ipairs( conditions ) do

    name, relation, value = unpack( clause )

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

	table.insert( self.conditions, { name, relation, value } )

  end

  return self

end

function SQL:OR( conditions ) return SQL:OR_WHERE( conditions ) end
function SQL:OR_WHERE( conditions )
  return self
end

function SQL:IN( name, values )
  return self
end


function SQL:NOT_IN( name, values )
  return self
end


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


  for _, condition in ipairs( self.conditions ) do
    name, relation, value = unpack( condition )

	statement = statement .. "\n  " .. name .. ' ' .. relation .. ' ' .. value .. 'AND'
  end

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
  :WHERE {
	{ 'u.id', '=', 12 },
	{ 'lastname', '>=', "Davidson's" }
  }
  :OR {
	{ '1', '=', 1 },
	{ '2', '=', 2 }
  }
  :AND {
    { 'firstname', '=', 'Daniel' }
  }
  :IN {
	'email', { 1, 2, 3, 4, 5 }
  }
  :NOT_IN {
	'email', { 7, 8 }
  }

print( query )

-- return SQL

