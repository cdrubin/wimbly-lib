
class = require 'middleclass'

local SQL = class( 'SQL' )

function SQL:__tostring()
  -- call statement or vice-versa
end

SQL.verb = ''
SQL.columns = {}


function SQL:initialize( verb )
  self.verb = verb
end


function SQL.static:select( columns )
  return SQL:new( 'select' ):select( columns )
end


function SQL:select( columns )

  for name, alias in pairs( columns ) do
	if alias == nil then alias = name end
	self.columns[alias] = name
  end

  return self
end


function SQL:statement()
  local statement = "SELECT\n"

  for alias, name in pairs( columns ) do
    statement = statement .. "\n  " .. name .. " AS " .. alias
  end

  return statement
end


--return SQL
print( SQL.select( { 'id', 'firstname', 'lastname' } ):statement() )


-- return SQL
