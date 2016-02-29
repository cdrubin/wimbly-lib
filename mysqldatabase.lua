
--local Model = require( 'models/base' )
local MySQLDatabase = class( 'MySQLDatabase' )--, Model )


function MySQLDatabase.static:connect( connection_settings )

  local object = MySQLDatabase:new()

  object.host = connection_settings.host
  object.database = connection_settings.database
  object.username = connection_settings.username
  local password = connection_settings.password

  if not ngx.ctx.mysql then
    ngx.ctx.mysql = {}
  end

  if not ngx.ctx.mysql[ object.host..object.database..object.username ] then

    local mysql = require( 'resty.mysql' )
    local db = mysql:new()

    local ok, err, errno, sqlstate = db:connect{
      host = object.host,
      port = 3306,
      database = object.database,
      user = object.username,
      password = password,
      max_packet_size = 1024 * 1024
    }

    if not ok then
	  error( 'failed to connect: ' .. err .. ': ' .. (errno or '') .. ' ' .. (sqlstate or '') )
    end

    ngx.ctx.mysql[ object.host..object.database..object.username ] = db
  end

  return object

end


function MySQLDatabase:query( sql_statement )

  ngx.log( ngx.DEBUG, "\n"..sql_statement )
  ngx.ctx.sql = sql_statement:gsub( '\n  ', ' ' ):gsub( '\n', ' ' )

  local db = ngx.ctx.mysql[ self.host..self.database..self.username ]
  if not db then
	error( 'failed to access object\'s db connection' )
  end

  local res, err, errorcode, sqlstate = db:query( sql_statement )

  if err then
	--error( err .. ' "' .. sql_statement .. '"' ) --inspect( { err = err, errorcode = errorcode, sqlstate = sqlstate, query = sql_statement } )  )
	error( { err, sql_statement } )
  end

  return res, err, errorcode, sqlstate
end


function MySQLDatabase:value( sql_statement )
  local result = self:result( sql_statement )
  if result then
    local key = next( result )
    local value = result[key]
    if type( value ) == 'string' and value:match( '^-?%d+%.?%d*$' ) then
      return tonumber( value )
    else
      return value
    end
    --return result[key]
  end
end


function MySQLDatabase:result( sql_statement )

  local res = self:resultset( sql_statement )
  --ngx.say( inspect( res ) )
  if res and #res > 0 then
    return res[1]
  else
    return nil
  end

end


function MySQLDatabase:resultset( sql_statement )

  local res, err, errno, sqlstate = self:query( sql_statement )

  if res then
    for _, row in ipairs( res ) do

      -- handle JSON by checking names of columns for those ending in _details
      for name, value in pairs( row ) do
        if name:match( 'details$' ) or name:match( 'json$' ) then
          if type( value ) == 'string' and value:trim() ~= '' then
            row[name] = cjson.decode( value )
          -- handle NULL and empty string
          elseif type( value ) == 'userdata' or type( value == 'string' and value:trim() == '' ) then
            row[name] = {}
          end
        end
      end


      --[[
      if row.details ~= nil then
        if type( row.details ) == 'string' and row.details:trim() ~= '' then
          row.details = cjson.decode( row.details )
        -- handle NULL and empty string
        elseif type( row.details ) == 'userdata' or type( row.details == 'string' and row.details:trim() == '' ) then
          row.details = {}
        end
      end -- if details column present
      --]]

    end -- for loop
  end -- if res

  return res

end



function MySQLDatabase:indexedresultset( sql_statement, indexby )

  local results = self:resultset( sql_statement )
  local indexedresults = {}

  for _, row in ipairs( results ) do
    indexedresults[ tostring( row[indexby] ) ] = row
  end

  return indexedresults

end


-- only supports simple PRIMARY KEY
function MySQLDatabase:update( table_name, id, changes )
  local primary_key_column = 'id'

  -- if no changes table then assume that id of row to update and changes are merged together in second parameter
  if not changes then
    changes = table.copy( id )
    id = changes[primary_key_column]
    changes[primary_key_column] = nil
  else
    if type( id ) == 'table' then
      for key, value in pairs( id ) do
        primary_key_column = key
        id = value
        break
      end
    end
  end

  local values = {}
  local i = 1
  for key, value in pairs( changes ) do
    --ngx.say( key, ' ', type(value), ' ', inspect(value) )
    if type( value ) == 'string' then
      values[i] = key.." = '"..value:gsub( "'", "%\\'" ).."'"
      i = i + 1
    elseif type( value ) == 'number' then
      values[i] = key.." = "..value
      i = i + 1
    elseif value == ngx.null then
      values[i] = key.." = NULL"
      i = i + 1
    elseif type( value ) == 'table' and key == 'details' then
      -- details gets encoded as JSON as it enters the database

      local cleaned = cjson.encode( value )
      -- remove quotes
      cleaned = cleaned:gsub( "'", "%\\'" )
      -- handle escapes
      cleaned = cleaned:gsub( "\\([^'])", '\\\\%1' )

      values[i] = key.." = '"..cleaned.."'"

      i = i + 1
    end
  end

  -- add quotes if primary key is a string
  if type( id ) == 'string' then
    id = "'"..id.."'"
  end

  local set_clause = table.concat( values, ',\n  ' )

  local query = string.interpolate( [[
UPDATE
  %(tablename)s
SET
  %(setclause)s
WHERE
  %(primarykeycolumn)s = %(primarykey)s
]], { tablename = table_name, setclause = set_clause, primarykeycolumn = primary_key_column, primarykey = id } )

  return self:query( query )

end


function MySQLDatabase:insert( table_name, row )

  local values = {}
  local i = 1

  --ngx.say( table_name, inspect( row ) )

  for key, value in pairs( row ) do
    --ngx.say( key, ' ', type(value), ' ', inspect(value) )
    if type( value ) == 'string' then
      values[i] = key.." = '"..value:gsub( "'", "%\\'" ).."'"
      i = i + 1
    elseif type( value ) == 'number' then
      values[i] = key.." = "..value
      i = i + 1
    elseif type( value ) == 'table' and key == 'details' then
      if next( value ) == nil then
        values[i] = key.." = NULL"
      else
        -- details gets encoded as JSON as it enters the database

        local cleaned = cjson.encode( value )
        -- remove quotes
        cleaned = cleaned:gsub( "'", "%\\'" )
        -- handle escapes
        cleaned = cleaned:gsub( "\\([^'])", '\\\\%1' )

        values[i] = key.." = '"..cleaned.."'"

      end
      i = i + 1
    end
  end

  local set_clause = table.concat( values, ',\n  ' )

  local query = string.interpolate( [[
INSERT INTO
  %(tablename)s
SET
  %(setclause)s
]], { tablename = table_name, setclause = set_clause } )

  return self:query( query )

end


function MySQLDatabase:delete( table_name, id )

  local query = string.interpolate( [[
DELETE FROM
  %(tablename)s
WHERE
  id = %(id)s
]], { tablename = table_name, id = id } )

  return self:query( query )

end


return MySQLDatabase
