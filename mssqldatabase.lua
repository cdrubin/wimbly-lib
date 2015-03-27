
--local Model = require( 'models/base' )
local MSSQLDatabase = class( 'MSSQLDatabase' )--, Model )

local luasql = require( 'odbc.luasql' )

MSSQLDatabase.static.environment = assert( luasql.odbc() )
--MSSQLDatabase.connection = nil

--db.con = assert( db.env:connect("streamline","lua","M0n4ay") )

function MSSQLDatabase.static:connect( dsn, username, password )

  local object = MSSQLDatabase:new()
  object.connection = MSSQLDatabase.environment:connect( dsn, username, password )

  return object
end


function MSSQLDatabase.static:streamline( yearstring )
  if not yearstring then
    local today = date( ngx.now() )
    if today:getmonth() < 9 then
      yearstring = ( today:getyear() - 1 )..'-'..today:getyear()
    else
      yearstring = today:getyear()..'-'..today:getyear() + 1
    end
  end

  return MSSQLDatabase:connect( 'streamline-'..yearstring, 'lua', 'M0n4ay' )
end


--
--
-- data access methods
--
--
function MSSQLDatabase:result( sql_statement )
  ngx.log( ngx.DEBUG, '\n'..sql_statement )
  --ngx.log( ngx.DEBUG, inspect( self.connection:execute( sql_statement ) ) )
  local cursor = assert( self.connection:execute( sql_statement ) )
  local result = cursor:fetch( {}, "a" )
  cursor:close()
  
  return result
end



-- all results in an iterator
--function MSSQLDatabase:results( sql_statement )
  --local cursor = assert( self.connection:execute( sql_statement ) )
  --return function()
    --return cursor:fetch()
  --end
--end


-- all results in an array of populated objects
function MSSQLDatabase:objectset( object, sql_statement )
  local cursor = assert( self.connection:execute( sql_statement ) )

  local results = {}

  repeat
    local result = cursor:fetch( {}, "a" )
	if result then
	  local obj = object:new( result )
	  results[#results + 1] = obj
	end
  until not result
  cursor:close()

  return results
end


-- all results in an array of populated objects
function MSSQLDatabase:indexedobjectset( object, sql_statement, indexby )
  local cursor = assert( self.connection:execute( sql_statement ) )

  local results = {}

  repeat
    local result = cursor:fetch( {}, "a" )
	if result then
	  local obj = object:new( result )
	  results[ tostring( result[indexby] ) ] = obj
	end
  until not result
  cursor:close()

  return results
end


-- all results in an array
function MSSQLDatabase:resultset( sql_statement, array )
  local mode = "a"
  if array then mode = "n" end

  local cursor = assert( self.connection:execute( sql_statement ) )

  local results = {}

  repeat
    local result = cursor:fetch( {}, mode )
	if result then results[#results + 1] = result end
  until not result
  cursor:close()
  --util.dump( results )

  return results
end


-- all results in an indexed table
function MSSQLDatabase:indexedresultset( sql_statement, indexby )
  local cursor = assert( self.connection:execute( sql_statement ) )

  local results = {}

  repeat
    local result = cursor:fetch( {}, "a" )
	--if result then util.dump( result[indexby] ) end
	if result then results[ tostring( result[indexby] ) ] = result end
  until not result
  cursor:close()

  --util.dump( results )

  return results
end


function MSSQLDatabase:execute( sql_statement )

  ngx.ctx.sql = sql_statement:gsub( '\n  ', ' ' ):gsub( '\n', ' ' )
  local result = self.connection:execute( sql_statement )

  return result
end


return MSSQLDatabase
