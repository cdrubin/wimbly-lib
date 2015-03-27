local validate = {
  type = {}
}



--[[
see Institute.propertyMapping for an example of a valid field to property mapping
--]]

-- example types:
-- string array
-- whole number array
-- sqldate
-- yesno array

--[[
function validate.field( name, value, mapping )
  if ( mapping == nil ) then
    return false, "unable to validate field '"..name.."' without a mapping"
  else

    -- don't use the original mapping table so that it does not get modified by validation
    local mapping = table.copy( mapping )

    if mapping.type and type( mapping.type ) == 'string' then

      -- handle an array of values if type ends with 'array'
      if mapping.type:ends( 'array' ) then
        mapping.type = mapping.type:match( '(.+)array' )
        if type( value ) == 'table' then
          for _, val in ipairs( value ) do
            local res, err = validate.field( name, val, mapping )
            if not res then return res, err end
          end
          mapping.type = nil
        end
      -- handle a string comma separated list if type ends with 'list'
      elseif mapping.type:ends( 'list' ) then
        mapping.type = mapping.type:match( '(.+)list' ):trim()
        if type( value ) == 'string' then
          local results = {}
          --ngx.say( 'here1' )
          for _, val in ipairs( value:split( ',' ) ) do
            --ngx.say( val )
            local res, err = validate.field( name, val, mapping )
            if not res then return res, err else end
          end
          mapping.type = nil
        end
      end

    end

    -- cannot handle table values
    if mapping.type and type( value ) == 'table' then
      return false, "validate can only occur on table values if the mapping type ends with 'array'"
    end

    -- if a mapping type was specified
    if mapping.type and type( mapping.type ) == 'string' and value ~= false then

      -- remove spaces and underscores from type
      mapping.type = mapping.type:gsub( '[_ ]', '' ):lower()

      if mapping.type == 'sqldatetime' then
        if not validate.type.sqldatetime( value ) then
          return false, "'"..name.."' requires a valid SQL datetime, '"..value.."' is invalid"
        end
      elseif mapping.type == 'sqldate' or mapping.type == 'date' then
        if not validate.type.sqldate( value ) then
          return false, "'"..name.."' requires a valid SQL date, '"..value.."' is invalid"
        end
      elseif mapping.type == 'integer' or mapping.type == 'integernumber' then
        if not validate.type.integernumber( value ) then
          return false, "'"..name.."' requires a integer number value, '"..value.."' is invalid"
        end
      elseif mapping.type == 'rational' or mapping.type == 'rationalnumber' then
        if not validate.type.rationalnumber( value ) then
          return false, "'"..name.."' requires a rational number value, '"..value.."' is invalid"
        end
      elseif mapping.type == 'wholenumber' then
        if not validate.type.wholenumber( value ) then
          return false, "'"..name.."' requires a whole number value, '"..value.."' is invalid"
        end
      elseif mapping.type == 'boolean' then
        if not validate.type.boolean( value ) then
          return false, "'"..name.."' must be of type 'boolean', '"..type( value ).."' is invalid"
        end
      elseif mapping.type == 'enumeration' then
        if not validate.type.enumeration( value, mapping.values ) then
          local values
          if table.isarray( mapping.values ) then values = mapping.values else values = table.keys( mapping.values ) end
          return false, "'"..name.."' must be of one of '"..table.concat( values, "', '" ).."'"
        end
      elseif mapping.type == 'email' or mapping.type == 'emailaddress' then
        if not validate.type.emailaddress( value ) then
          return false, "'"..name.."' must be a valid email address, '"..value.."' is invalid"
        end
      elseif mapping.type == 'yesno' then
        if not validate.type.yesno( value ) then
          return false, "'"..name.."' must be either 'yes' or 'no', '"..value.."' is invalid"
        end
      elseif mapping.type == 'string' then
        if not type( value ) == 'string' then
          return false, "'"..name.."' should be of type 'string', '"..type( value ).."' is invalid"
        end
      else
        return false, "no method found to validate '"..name.."' as type '"..mapping.type.."'"
      end

    end

    -- if a mapping pattern was specified
    if mapping.pattern and value ~= false and type( value ) == 'string' and not value:match( mapping.pattern ) then
      if mapping.hint then
        return false, mapping.hint
      else
        return false, "'"..name.."' fails pattern validation '"..mapping.pattern.."'"
      end
    end

    -- if a validation function was provided in mapping
    if mapping.validation and type( mapping.validation ) == 'function' then
      return mapping.validation( value )
    end

  end -- if a mapping entry exists

  return true
end
--]]

--[[
function validate.fields( fields, mapping, options )
  local options = options or {}

  local errors = {}

  -- check for existence and required
  for name, values in pairs( mapping ) do
    if values.required and options.create and fields[name] == nil then
      table.insert( errors, { name = name, message = "'"..name.."' is required" } )
    end
  end


  for name, value in pairs( fields ) do

    -- if options.update is set then readonly must be enforced
    if value and mapping[name] and mapping[name].readonly and options.update then
      table.insert( errors, { name = name, message = "'"..name.."' is readonly" } )
    end

    local valid, message = validate.field( name, value, mapping[name] )
    if not valid then
      table.insert( errors, { name = name, message = message } )
    end

  end -- iterate through the values

  return #errors == 0, errors

end
--]]

--[[
function validate.convert( name, value, typ, options )
  local options = options or {}

  if type( name ) ~= 'string' or type( value ) ~= 'string' or type( typ ) ~= 'string' then
    ngx.exit( ngx.OK )
    error( "convert must be called with strings" )
  end

  local success = true

  local original = value
  if typ:match( '^integer' ) or typ:match( '^rational' ) or typ:match( 'number' ) then
    -- an empty string should convert to nil instead of zero
    if value:trim() == '' then
      value = nil
    else
      value = tonumber( original )
      if not original:match( tostring( value ) ) then success = false end
    end
  elseif typ:match( '^boolean' ) then
    value = ( value:trim():lower() == 'true' )
    if not ( original:lower():trim() == 'true' or original:lower():trim() == 'false' ) then success = false end
  end

  if options.unescape and type( value ) == 'string' then
    value = ngx.unescape_uri( value )
  end

  return success, value
end
--]]

--[[
function validate.transform2( posted, mapping, options )
  local options = options or {}

  local errors = {}
  local cleaned = table.copy( posted )

  return #errors == 0, errors, cleaned
end
--]]

--[[
function validate.transform( posted, mapping, options )
  local options = options or {}

  local errors = {}
  local cleaned = table.copy( posted )

  -- check that all required fields are present
  if options.create then
    for name, values in pairs( mapping ) do
      if ( not cleaned[name] or ( type( cleaned[name] ) == 'string' and cleaned[name]:trim() == '' ) ) and values.required then
        table.insert( errors, { name = name, message = "'"..name.."' is required" } )
      end
    end
  end

  local converted, success

  --ngx.say( 'transform', inspect( cleaned ) )

  -- if valid conversions convert posted string fields to the intended data types in 'cleaned'
  for name, value in pairs( cleaned ) do
    if type( name ) ~= 'string' then error( "table 'posted' must be composed only of string keys" ) end

    if type( value ) == 'table' and mapping[name].type then

      converted = {}

      for index, val in ipairs( value ) do
        if type( val ) == 'string' then
          if mapping[name].type then
            success, converted[index] = validate.convert( name, val, mapping[name].type, options )
            if not success then table.insert( errors, { name = name, message = "value in '"..name.."' table could not be converted to type '"..mapping[name].type.."'" } ) end
          else
            converted[index] = val
          end
        else
          table.insert( errors, { name = name, message = "'"..name.."' must be a table of strings" } )
        end
      end
    elseif type( value ) == 'table' then
      -- XXX just make it JSON until recursive validation is added
      converted = cjson.encode( value )

    elseif type( value ) == 'string' then
      if mapping[name] and mapping[name].type then
        success, converted = validate.convert( name, value, mapping[name].type, options )
        if not success then table.insert( errors, { name = name, message = "value in '"..name.."' field could not be converted to type '"..mapping[name].type.."'" } ) end
      else

        -- check if part of an array
        -- iterate


        converted = value
      end
    else
      table.insert( errors, { name = name, message = "'"..name.."' must be of type string" } )
    end

    cleaned[name] = converted
  end

  return #errors == 0, errors, cleaned
end
--]]

--[[
function validate.for_creation( posted, mapping, options )
  -- check that all required fields are present
  local options = options or { create = true }

  if ( mapping == nil ) then
    return false, "unable to validate"
  end

  local transform_success, transform_errors, cleaned = validate.transform( posted, mapping, options )
  -- don't show create (required) errors twice

  --ngx.say( 'for_creation', inspect( cleaned ) )

  options.create = false
  local validation_success, validation_errors = validate.fields( cleaned, mapping, options )

  local errors = {}
  for i, err in ipairs( transform_errors ) do errors[i] = err end
  for i, err in ipairs( validation_errors ) do errors[#transform_errors + i] = err end

  return #errors == 0, errors, cleaned
end
--]]

function validate.mapping( values, mapping, options, name_so_far )
  local options = options or { ignore_required = false, ignore_readonly = false, report_unknown = false, zero_based_indexing = false }
  local name_so_far = ( name_so_far or '' )
  local errors = {}

  --ngx.say( '<hr />called with values: ', inspect( values ), '<br />', 'mapping: ', inspect( mapping ), '<br />', 'name_so_far: ', name_so_far, '<br />' )

  -- validate a simple value with a simple type
  local _validate = function( val, type, name )
    if validate.type[ type ] then
      local res, message = validate.type[ type ]( val )
      return message
    else
      error( "unknown type '"..( type or 'nil' ).."' at '"..name.."'" )
    end
  end

  -- seek the provided value in an enumeration of values
  local _enumerate = function( value, allowed, name )
    if type( allowed ) == 'table' then
      local found = false
      if table.isarray( allowed ) then
        for _, val in ipairs( allowed ) do
          if value == val then found = true; break end
        end
      else
        found = allowed[value]
      end
      if not found then
        return "'"..value.."' not found in list of allowed values at '"..name.."'"
      end
    else
      error( "non-table values at '"..name.."'" )
    end
  end


  -- mappings must be key-value tables not arrays
  if not type( mapping ) == 'table' or table.isarray( mapping ) then
    if name_so_far ~= '' then name_so_far = ' at '..name_so_far end
    error( "invalid mapping for validation"..name_so_far )
  end

  -- determine if a single mapping or a table of mappings
  -- (if every value is a table then is a table of mappings otherwise a single mapping)
  -- (also check we are not confusing a table of values with an inner type)
  local table_of_mappings = true
  for key, map in pairs( mapping ) do
    --ngx.say( '--- key: ', key, '<br />' )
    if type( map ) ~= 'table' or table.isarray( map ) or ( key == 'values' and not ( map.type or map.values ) ) then table_of_mappings = false end
  end

  -- check validity of table of mappings and recursively call validate.mapping with single mapping and corresponding value
  if table_of_mappings then

    if type( values ) == 'table' and table.isarray( values ) and mapping.type and not table.isarray( mapping.type ) then
      --ngx.say( 'values: ', inspect( values ), ', mapping: ', inspect( mapping ), ', isarray mapping: ', table.isarray( mapping ) )
      if name_so_far then name_so_far = ' at '..name_so_far end
      error( 'mapping table provided for validation of non-table data'..name_so_far )
    end

    -- check for unknown values if report_unknown
    if options.report_unknown then
      for name, _ in pairs( values ) do
        if mapping[name] == nil then
          local nsf
          if name_so_far ~= '' then
            if type( name ) == 'number' then
              if options.zero_based_indexing then name = name - 1 end
              nsf = name_so_far..'['..tostring(name)..']'
            else
              nsf = name_so_far..'.'..name
            end
          else
            nsf = name
          end
          table.insert( errors, { name = nsf, message = 'field not found in mapping and can not be validated' } )
        end
      end
    end

    -- iterate through mappings
    for name, map in pairs( mapping ) do
      local nsf ; if name_so_far ~= '' then nsf = name_so_far..'.'..name else nsf = name end

      local errs

      --ngx.say( '-----------\n name: ', inspect( name ), ', map: ', inspect( map ), '<br />' )
      --ngx.log( ngx.ERR, '-----------\n name: ', inspect( name ), ', map: ', inspect( map ), '<br />' )

      local vals
      if values == nil or values[name] == nil then
        vals = nil
      else
        vals = values[name]
      end

      if type ( map.type ) == 'table' and not table.isarray( map.type ) then
        _, errs = validate.mapping( vals, map.type, options, nsf )
      else
        _, errs = validate.mapping( vals, map, options, nsf )
      end
      for _, err in ipairs( errs ) do table.insert( errors, err ) end

    end

  -- handle a single mapping
  else

    if values ~= nil then
      if mapping.readonly and not options.ignore_readonly then
        table.insert( errors, { name = name_so_far, message = "value supplied for field marked readonly" } )

      -- actually validate the data
      else
        local to_type = mapping.type

        -- if potentially an array type
        if type( to_type ) == 'table' then

          if table.isarray( to_type ) and #to_type == 1 then  -- and type( to_type[1] ) == 'string' then
            if type( values ) == 'table' and table.isarray( values ) then
              local mod_mapping = table.copy( mapping )
              mod_mapping.type = to_type[1]
              for index, val in ipairs( values ) do
                if options.zero_based_indexing then
                  nsf = name_so_far..'['..(index - 1)..']'
                else
                  nsf = name_so_far..'['..index..']'
                end

                local errs
                if type( to_type[1] ) == 'string' then
                  _, errs = validate.mapping( values[index], mod_mapping, options, nsf )
                else
                  _, errs = validate.mapping( values[index], mod_mapping.type, options, nsf )
                end
                for _, err in ipairs( errs ) do table.insert( errors, err ) end
              end
            else
              if name_so_far ~= '' then name_so_far = ' at '..name_so_far end
              error( "array type provided for validation of non-array values"..name_so_far )
            end
          else
            if name_so_far ~= '' then name_so_far = ' at '..name_so_far end
            error( "invalid mapping for validation"..name_so_far )
          end

        -- if a simple type
        else

          if values then
            local error_message
            if mapping.validator then
              error_message = mapping:validator( name_so_far, values )
            else
              if not mapping.values then
                error_message = _validate( values, to_type, name_so_far )
              else
                error_message = _enumerate( values, mapping.values, name_so_far )
              end
            end
            if error_message then table.insert( errors, { name = name_so_far, message = error_message } ) end
          end

        end
      end

    -- value is nil
    elseif mapping.required and not options.ignore_required then
      table.insert( errors, { name = name_so_far, message = 'no value supplied for field marked required' } )
    end

  end

  return #errors == 0, errors
end


--[[
function validate.for_creation2( posted, mapping, options )
  local options = options or { create = true }

  if ( mapping == nil ) then
    return false, "unable to validate"
  end

  local transform_success, transform_errors, cleaned = validate.transform2( posted, mapping, options )
  -- don't show create (required) errors twice

  --ngx.say( 'for_creation', inspect( cleaned ) )

  options.create = false
  local validation_success, validation_errors = validate.fields( cleaned, mapping, options )

  local errors = {}
  for i, err in ipairs( transform_errors ) do errors[i] = err end
  for i, err in ipairs( validation_errors ) do errors[#transform_errors + i] = err end

  return #errors == 0, errors, cleaned
end
--]]


--[[
function validate.parameters( params, mapping )
  return validate.for_creation( params, mapping, { create = true, unescape = true } )
end
--]]

-- XXX : not needed
--function validate.parameters2( params, mapping )
  --return validate.mapping( params, mapping, { ignore_required = false, ignore_readonly = true } ) --create = true, unescape = true } )
--end

function validate.for_creation( values, mapping, options )
  local options = ( options or {} )

  local opts = { ignore_required = false, ignore_readonly = true }
  for key, value in pairs( options ) do
    opts[key] = value
  end
--ngx.say( '<pre>', inspect( values ), '<hr />', inspect( mapping ), '</pre>' )
  return validate.mapping( values, mapping, opts )
end


function validate.for_update( values, mapping, options )
  local options = ( options or {} )

  local opts = { ignore_required = true, ignore_readonly = false }
  for key, value in pairs( options ) do
    opts[key] = value
  end
  --ngx.say( '<pre>', inspect( values ), '<hr />', inspect( mapping ), '</pre>' )
  return validate.mapping( values, mapping, opts )
end

--[[
function validate.for_update( posted, mapping )
  -- check that all readonly fields are left alone
  local options = options or { readonly = true }

  if ( mapping == nil ) then
    return false, "unable to validate"
  end

  local transform_success, transform_errors, cleaned = validate.transform( posted, mapping, options )

  local validation_success, validation_errors = validate.fields( cleaned, mapping, options )

  local errors = {}
  for i, err in ipairs( transform_errors ) do errors[i] = err end
  for i, err in ipairs( validation_errors ) do errors[#transform_errors + i] = err end

  return #errors == 0, errors, cleaned
end
--]]

function validate.type.string( str )
  local valid = type( str ) == 'string'
  if not valid then
    return false, tostring( str )..' is not a string'
  else
    return true
  end
end


function validate.type.number( num )
  local valid = type( num ) == 'number'
  if not valid then
    return false, "'"..tostring( num ).."' is not a number"
  else
    return true
  end
end


--[[
function validate.type.enumeration( submitted, values )
  local vals = {}

  if table.isarray( values ) then
    for _, value in ipairs( values ) do
      vals[value] = value
    end
  else
    vals = values
  end

  if vals[submitted] then
    return true, vals[submitted]
  else
    return false, submitted
  end

end
--]]

function validate.type.sqldatetime( str )
  local str = tostring( str )
  local parts = str:split( ' ' )
  local valid = true

  if #parts == 2 then
    local datepart = validate.type.sqldate( parts[1] )

    local h, m, s = parts[2]:match( '^([0-2][0-9]):([0-5][0-9]):([0-5][0-9])$' )

    h = tonumber( h )

    if ( h ~= nil and m ~= nil and s ~= nil ) then
      valid = ( h <= 23 and datepart )
    else
      valid = false
    end
  else
    valid = false
  end

  if valid then
    return true
  else
    return false, "'"..str.."' is not a valid sqldatetime"
  end

end
validate.type['sql datetime'] = validate.type.sqldatetime


-- check whether string could be a sqldate
function validate.type.sqldate( str )
  local str = tostring( str )
  local y, m, d = str:match( '^([1-2][9,0]%d%d)%-([0-1][0-9])%-([0-3][0-9])$' )
  local valid = true

  if y ~= nil and m ~= nil and d ~= nil then

    y, m, d = tonumber( y ), tonumber( m ), tonumber( d )

    -- Apr, Jun, Sep, Nov can have at most 30 days
    if m == 4 or m == 6 or m == 9 or m == 11 then
      valid = d <= 30
    -- Feb
    elseif m == 2 then
      -- if leap year, days can be at most 29
      if y%400 == 0 or ( y%100 ~= 0 and y%4 == 0 ) then
        valid = d <= 29
      -- else 28 days is the max
      else
        valid = d <= 28
      end
    -- all other months can have at most 31 days
    else
      valid = d <= 31
    end
  else
    valid = false
  end

  if valid then
    return true
  else
    return false, "'"..str.."' is not a valid sqldate"
  end
end

-- check comma separated list of dates
--[[
function validate.type.sqldates( str )
  local dates = str:split( ',' )
  if #dates > 0 then
    for _, d in ipairs( dates ) do
      if not validate.type.sqldate( d ) then
        return false
      end
    end
    return true, str
  else
    return false, str
  end
end
--]]

-- check for a valid integer
function validate.type.integer( num )
  local str = tostring( num )
  local valid = type( num ) == 'number' and str:match( '^-?%d+$' )
  if not valid then
    return false, "'"..str.."' is not an integer"
  else
    return true
  end
end
validate.type.integernumber = validate.type.integer
validate.type['integer number'] = validate.type.integer

-- check for valid rational number
function validate.type.rational( num )
  local str = tostring( num )
  local valid = type( num ) == 'number' and str:match( '^-?%d+%.?%d-$' )
  if not valid then
    return false, "'"..str.."' is not a rational number"
  else
    return true
  end
end
validate.type.rationalnumber = validate.type.rational
validate.type['rational number'] = validate.type.rational

-- check for valid whole number
function validate.type.wholenumber( num )
  local str = tostring( num )
  local valid = type( num ) == 'number' and str:match( '^%d+$' )
  if not valid then
    return false, "'"..str.."' is not a whole number"
  else
    return true
  end
end
validate.type.whole = validate.type.wholenumber
validate.type['whole number'] = validate.type.wholenumber

function validate.type.boolean( bool )
  local str = tostring( bool )
  local valid = type( bool ) == 'boolean'
  if not valid then
    return false, "'"..str.."' is not a boolean"
  else
    return true
  end
end
validate.type.bool = validate.type.boolean

--function validate.type.yesno( str )
  --local cleaned = tostring( str )
  --cleaned = str:lower():trim()
  --return ( cleaned == 'yes' or cleaned == 'no' ), cleaned
--end

function validate.type.email( str )
  local str = tostring( str )
  local valid = str:match( "[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?" )
  local message
  if not valid then message = "'"..str.."' is not a valid email address" end
  return valid, message
end
validate.type.emailaddress = validate.type.email

return validate
