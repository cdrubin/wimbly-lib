
--- <b>TablesModel</b> for use when modelling objects based on database table rows.
-- <br />
--
-- @class module

--[[
module 'model/_tables'
--]]

local BaseModel = require( 'model/base' )
local TablesModel = class( 'TablesModel', BaseModel )

TablesModel.static.connectionSettings = {}

--- Derived classes provide the names of the database tables for the data rows that back the object.
-- <br />
-- <pre>
-- SomeModel.tableNames = { <br />
-- &nbsp;&nbsp;person = 'people', <br />
-- &nbsp;&nbsp;school = 'organization' <br />
-- }
-- </pre>
-- @class table
-- @name TablesModel.static.tableNames
TablesModel.static.tableNames = {}

TablesModel.static.query = {}

---
-- Establishes a database connection to <i>back</i>
-- <br />
-- Initializes data structures for storage of row data and tracking of updates to that data
function TablesModel:initialize()
  BaseModel.initialize( self )

  self.db = require( 'mysqldatabase' ):connect( self.class.static.connectionSettings )
  self.rows = {}
  self.updated = {}
end


---
-- Return the underlying data of an object.
-- @return <i>table</i>
function TablesModel:_desicate()
  return self.rows
end


---
-- Replace the underlying data of an object.
-- @param data <i>table</i>
-- @return <i>table</i> self
function TablesModel:_hydrate( rows )
  if not rows then return nil end

  self.rows = rows;
  return self;
end


---
-- Access a single data element with the option of doing so without using the fieldMapping location.
-- @param name <i>string</i> data element name
-- @param options <i>table</i> defaults to <tt>{ direct = false }</tt>
function TablesModel:_get( name, options )
  local options = options or { direct = false }

  --[==[
  if self.class.fieldMapping[name] == nil then
    ngx.say( 'name: ', inspect( name ), ', options: ', inspect( options ) )
  end

  local location
  if not options.direct then --and not self.class.fieldMapping[name].direct then
    location = self.class.fieldMapping[name].location
    if not location then
      if not options.safe then
        error( 'field '..name..' of '..self.class.name..' has no location defined in fieldMapping.', 2 )
      else
        return nil
      end
    end
  else
    location = name
  end
  return table.dotget( self, 'rows.'..location )
  --]==]

  --ngx.say( 'rows-> ', inspect( self.rows ), ' <-rows' )

  return table.dotget( self, 'rows.'..name )

end

---
-- Update the objects underlying data store by iterating through the
-- updated rows and calling a db update on the content of each indicated row.
function TablesModel:_update()

  for location, _ in pairs( self.updated ) do
    self.db:update( self.class.tableNames[ location ], table.dotget( self, 'rows.'..location ) )
    self.updated[ location ] = nil
  end
end


---
-- Modify a single data element with the option of doing so without using the fieldMapping location.
-- @param name <i>string</i> data element name
-- @param value new value
-- @param options <i>table</i> defaults to <tt>{ direct = false }</tt>
function TablesModel:_set( name, value, options )
  local options = options or { direct = false }


--[[
  local location

  if not options.direct then
    location = self.class.fieldMapping[name].location
    if not location then --and not options.direct then
      error( 'field '..name..' of '..self.class.name..' has no location defined in fieldMapping.', 2 )
    end
  else
    location = name
  end


  -- mark the table row as updated if necessary
  for row_location, _ in pairs( self.class.tableNames ) do
    if location:starts( row_location ) then self.updated[ row_location ] = true end
  end

  --ngx.say( '_set', name, value )

  return table.dotset( self, 'rows.'..location, value ), path
--]]

  -- mark the table row as updated if necessary
  for row_location, _ in pairs( self.class.tableNames ) do
    if name:starts( row_location ) then self.updated[ row_location ] = true end
  end

  --ngx.say( '_set', name, value )

  return table.dotset( self, 'rows.'..name, value ), path

end


---
-- Insert a newly instantiated object's underlying data using db insert
-- @param callback <i>function</i> called with <b>location</b> parameter after successful insert of each data row
-- @param order <i>array</i> ordered list of the <a href="#TablesModel.static.tableNames">tableNames</a> keys to insert
function TablesModel:_insert( callback, order )

  local __insert = function( object, source )
    local database_table = self.class.tableNames[ source ]
    local result, err, errcode, sqlstate = self.db:insert( database_table, table.dotget( object, 'rows.'..source ) )
    if result and result.affected_rows == 1 then
      table.dotset( object, 'rows.'..source..'.id', result.insert_id )
    else
      error( err )
    end
  end

  if order then
    for _, location in ipairs( order ) do
      __insert( self, location )
      if callback and type( callback ) == 'function' then callback( location ) end
    end
  else
    for location, _ in pairs( self.class.tableNames ) do

      if self.rows[location] then
        __insert( self, location )
        if callback and type( callback ) == 'function' then callback( location ) end
      end

    end
  end

end

return TablesModel
