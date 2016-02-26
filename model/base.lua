
--- <b>BaseModel</b> that defines interface.
-- <br />
-- Various ways to construct infinite lists.
-- @class module

--[[
module 'model/_base'
--]]


local BaseModel = class( 'BaseModel' )


--- Derived classes provide describe each field with attibutes.
-- <br />
-- Supported attributes are:
-- <ul>
--   <li><tt> type = '&lt;data-type&gt;'</tt> <br />
--   <pre>
--          <table class="bnf">
--            <tr><td>&lt;data-type&gt;</td><td>::=</td><td>&lt;element-type&gt; &lt;collection-type&gt;</td></tr>
--            <tr><td>&lt;element-type&gt;</td><td>::=</td><td>integer | whole number | sql date | string | <i>nil</i></td></tr>
--            <tr><td>&lt;collection-type&gt;</td><td>::=</td><td>list | array | </td></tr>
--          </table>
--   </pre>
--          used for validation on updates and insertions <br /><br />
--   <li><tt>mutator = <i>function</i></tt> <br />
--          function is called with the new value when .set() is called <br /><br />
--   <li><tt> accessor = <i>function</i></tt> <br />
--          function is called to return value when .get() is called
-- </ul>
-- <pre>
--SomeModel.fieldMapping = { <br />
-- &nbsp;&nbsp;name = { type = 'string',  }, <br />
-- &nbsp;&nbsp;email = { } <br />
-- }
-- </pre>
-- @class table
-- @name BaseModel.static.fieldMapping
BaseModel.static.fieldMapping = {
}

-- extension types for this model
BaseModel.static.type = {
}


function BaseModel:initialize()
end


function BaseModel:_desicate()
  error( 'no default implementation of _get in base class', 3 )
  -- implementations should raise errors
end


function BaseModel:_hydrate( data )
  error( 'no default implementation of _get in base class', 3 )
  -- implementations should raise errors
end


function BaseModel:_get( name, options )
  error( 'no default implementation of _get in base class', 3 )
  -- implementations should raise errors
  -- just return value
end


-- direct is equivalent in functionality to something like 'name_as_location_ignore_mapping'
function BaseModel:get( name, options )
  local options = options or { safe = false, ignore_accessor = false, direct = false, as_array = false, as_table = false }

  local __get = function( name, options )

    -- return value directly
    if options.direct then

      return self:_get( name, options )

    -- use features of fieldMapping
    else

      -- there must be a fieldmapping
      if not self.class.fieldMapping[name] then
        error(  "field '"..name.."' of '"..self.class.name.."' has no mapping in fieldMapping.", 2 )
      end

      -- use accessor if there is one
      if not options.ignore_accessor and type( self.class.fieldMapping[name].accessor ) == 'function' then
        return self.class.fieldMapping[name].accessor( self, name, options )

      -- otherwise use 'default' get mechanism
      else

        -- location defaults to name
        local location = name

        -- use location if provided
        if self.class.fieldMapping[name].location then
          location = self.class.fieldMapping[name].location
        end

        -- translate to value at key in values table if need be
        if self.class.fieldMapping[name].values and type( self.class.fieldMapping[name].values ) == 'table' and not table.isarray( self.class.fieldMapping[name].values ) then
          return table.indexof( self.class.fieldMapping[name].values, self:_get( location, options ) )
        end

        return self:_get( location, options )

      end

    end

  end



  local names = {}
  -- convert single value name into table of names
  if name == nil then
    error( "no field name provided for access in '"..self.class.name.."'", 2 )
  elseif type( name ) == 'string' then
    names = { name }
  else
    names = name
  end

  local results = {}
  for i, field in ipairs( names ) do
    local result = __get( field, options )
    results[i] = result
  end

  if options.as_array then
    return results
  elseif options.as_table then
    local res = {}
    for i, field in ipairs( names ) do
      res[names[i]] = results[i]
    end
    return res
  else
    return unpack( results )
  end


end


-- iterates through the fieldMapping and calls object:get(...) on each item
function BaseModel:data()
  local results = {}
  for name, _ in pairs( self.class.fieldMapping ) do
    results[name] = self:get( name, { safe = true } )
  end
  return results
end



function BaseModel:_set( name, value, options )
  error( 'no default implementation of _set in base class', 3 )
  -- implementations should raise errors
  -- no return values used
end


function BaseModel:_update()
  error( 'no default implementation of _update in base class', 2 )
  -- implementations should raise errors
end


function BaseModel:set( namevals, value, options )
  local options = options or { skip_update = false, skip_validation = false, ignore_mutator = false, direct = false }

  if options.direct then options.skip_validation = true end

  local __set = function( name, value, options )

    if not options.skip_validation then
      local valid, err = self.class:validate( name, value )
      if not valid then
        error( err, 3 )
      end
    end

    -- change value directly
    if options.direct then

      self:_set( name, value, options )

    -- use features of fieldMapping
    else

      -- there must be a fieldmapping
      if not self.class.fieldMapping[name] then
        error( "field '"..name.."' of '"..self.class.name.."' has no mapping in fieldMapping.", 2 )
      end

      -- use mutator if there is one
      if not options.ignore_mutator and type( self.class.fieldMapping[name].mutator ) == 'function' then
        self.class.fieldMapping[name].mutator( self, name, value, options )

      -- otherwise use 'default' set mechanism
      else

        -- location defaults to name
        local location = name

        -- use location if provided
        if self.class.fieldMapping[name].location then
          location = self.class.fieldMapping[name].location
        end

        -- translate to value at key in values table if need be
        if self.class.fieldMapping[name].values and type( self.class.fieldMapping[name].values ) == 'table' then
          if self.class.fieldMapping[name].values[value] ~= nil then
            value = self.class.fieldMapping[name].values[value]
          end
        end

        self:_set( location, value, options )

      end

    end

  end

  -- convert single value name into table of names
  if namevals == nil then
    error( "no field name or name-value table provided for mutation in '"..self.class.name.."'", 2 )
  elseif type( namevals ) == 'string' then
    namevals = { [namevals] = value }
  end

  for name, value in pairs( namevals ) do
    __set( name, value, options )
  end

  -- updated_on handling
  if self.class.fieldMapping['updated_on'] then
    self:_set( 'updated_on', os.date( '%Y-%m-%d %X', os.time() ) )
  end

  if not options.skip_update then self:_update() end

  return self

end


function BaseModel:_insert()
  error( 'no default implementation of _insert in base class', 2 )
  -- implementations should raise errors
  -- should return the new object or nil on failure
end


-- derived classes must implement _insertData
function BaseModel.static:insert( setup, options )
  local options = { skip_validation = false, skip_insert = false }

  local object = self:new()

  if not options.skip_validation then
    local valid, errors = validate.for_creation( setup, self.fieldMapping )

    if not valid then
      error( errors[1].message, 2 )
    end
  end

  for key, value in pairs( setup ) do
    object:set( key, value, { skip_update = true } )
  end

  -- set created timestamp
  if self.fieldMapping['created_on'] then
    object:set( 'created_on', os.date( '%Y-%m-%d %X', os.time() ), { skip_update = true } )
  end

  if not options.skip_insert then
    object:_insert()
  end

  return object
end


function BaseModel:_delete()
  error( 'no default implementation of _delete in base class', 3 )
  -- implementations should raise errors
  -- no return values used
end


function BaseModel:delete()
  self:_delete()
end


-- derived classes inherit validation based on the rules present in their detailMapping
function BaseModel.static:validate( name, value )

  if type( name ) == 'string' then
    local input = {}
    input[name] = value
    --ngx.say( '    input: ', inspect( input ), '<br />' )
    return validate.mapping( input, self.fieldMapping, { ignore_required = true, ignore_readonly = true } )
  else
    return validate.mapping( name, self.fieldMapping, { ignore_required = true, ignore_readonly = true } )
  end

end

return BaseModel
