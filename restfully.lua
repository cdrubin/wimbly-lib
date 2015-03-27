local RESTfully = {
  GET = {},
  POST = {}
}


function RESTfully.json( content )
  --local content = content or ''

  if type( content ) ~= 'string' then
    content = cjson.encode( content )
  end

  if ngx.var.arg_callback then
    if ngx.header.content_type ~= 'text/javascript' then
      ngx.header.content_type = 'text/javascript'
    end
    ngx.say( ngx.var.arg_callback..'( '..content..' );' )
  else
    if ngx.header.content_type ~= 'text/json' then
      ngx.header.content_type = 'text/json'
    end
    ngx.say( content )
  end
end


function RESTfully.respond( content, ngx_status )
  local ngx_status = ngx_status or ngx.status

  ngx.status = ngx_status
  restfully.json( content )
  return ngx.exit( ngx.OK )
end

--[[
function RESTfully.validate( parameters_mapping )

  local params = {}
  for name, mapping in pairs( parameters_mapping ) do
    params[name] = mapping.location
  end

  local success, errors, cleaned = validate.parameters( params, parameters_mapping )
  if not success then
    return restfully.respond( errors, ngx.HTTP_BAD_REQUEST )
    --restfully.json( errors )
    --return ngx.exit( ngx.OK )
  end

  return cleaned

end
--]]

-- XXX:
-- TODO: keep same or similar validate function but add restfully.arguments function that

function RESTfully.arguments( options )
  local options = ( options or { uri = true, post = true } )

  -- populate ctx with arguments if not already done so
  if options.uri then
    ngx.ctx.uri = restfully.uri_args_to_table( ngx.req.get_uri_args() )
  end
  if ngx.req.get_method() == 'POST' and options.post then
    ngx.req.read_body()
    ngx.ctx.post = restfully.post_args_to_table( ngx.req.get_post_args() )
  end

  return ngx.ctx.uri, ngx.ctx.post
end


-- accept values table and mapping or a combined single table
function RESTfully.validate( values_and_mapping, options )
  local options = ( options or { coerce_types = true } )

  local values = {}
  for name, map in pairs( values_and_mapping ) do
    values[name] = RESTfully._string_type_convert( map.location, map.type, name )
  end

  local success, errors = validate.for_creation( values, values_and_mapping )

  if not success then
    return restfully.respond( errors, ngx.HTTP_BAD_REQUEST )
  else
    return values
  end
end

--[[
--]]

function RESTfully._generate_human_readable_model_name( model_path )
  local parts = model_path:split( '/' )
  local model_name = parts[#parts]:gsub( '_', ' ' )
  return model_name
end

-- !!!
-- TODO, this should accept a 4th parameter of the fields that should be returned
-- and it should rely on the object get call that allows more than one field to be specified,
-- and those should be returned in a table
-- !!!
function RESTfully.GET.data( model_path, loader, load_parameter )

  local BusinessModel = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  local business_object
  local parameter = ngx.var['arg_'..load_parameter ]

  if parameter ~= nil then
    business_object = BusinessModel[loader]( BusinessModel, ngx.unescape_uri( parameter ) )
  end

  if business_object ~= nil then
    results = business_object:data()
  else
    if not ngx.var.arg_callback then
      ngx.status = ngx.HTTP_BAD_REQUEST
    else
      -- jsonp
      results.success = false
    end
    results.message = model_name..' not found'
  end

  RESTfully.json( results )

end


function RESTfully.GET.metadata( model_path )

  local BusinessModel = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  -- store the relative order
  local ordered = {}

  for key, values in pairs( BusinessModel.fieldMapping ) do
    if not values.generated then
      results[key] = {
        type = values.type,
        required = ( values.required or false ),
        order = values.order,
        readonly = ( values.readonly or false ),
      }

      if values.values and type( values.values ) == 'table' then
        if table.isarray( values.values ) then
          results[key].values = values.values
        else
          results[key].values = table.keys( values.values )
        end
      end

      if values.order then ordered[values.order] = key end
    end
  end

  -- update the order numbers
  local order = 1
  for i = 1, table.getn( ordered ) do
    if ordered[i] ~= nil then
      results[ ordered[i] ].order = order
      order = order + 1
    end
  end

  RESTfully.json( results )

end

--[[

function RESTfully.POST.create( model_path )

  local BusinessModel = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  -- must read the request body up front
  ngx.req.read_body()
  local posted = ngx.req.get_post_args()

  local valid, errors, cleaned = validate.for_creation( posted, BusinessModel.fieldMapping )

  local results = {}
  local model = nil

  if not valid then
    ngx.status = ngx.HTTP_BAD_REQUEST
    results.message = 'submitted '..model_name..' values are invalid'
    results.errors = errors
  else
    model = BusinessModel:insert( cleaned )
    if not model then
      ngx.status = ngx.HTTP_BAD_REQUEST
      results.message = model_name..' creation failed'
    else
      results.message = model_name..' created successfully'
      results.details = model:data()
    end
  end

  RESTfully.json( results )
  return model

end
--]]


function RESTfully.POST.create( model_path )

  local Model = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  -- must read the request body up front
  ngx.req.read_body()
  --ngx.say( inspect( ngx.req.get_post_args() ) )
  -- coerce types to resemble fieldMapping as closely as possible
  local posted = RESTfully.post_args_to_table( ngx.req.get_post_args(), Model.fieldMapping )

  --ngx.say( inspect( posted ) )

  local valid, errors = validate.for_creation( posted, Model.fieldMapping, { zero_based_indexing = true } )

  if not valid then
    ngx.status = ngx.HTTP_BAD_REQUEST
    results.message = 'submitted '..model_name..' values are invalid'
    results.errors = errors
  else
    local object = Model:insert( posted )
    if not object then
      ngx.status = ngx.HTTP_BAD_REQUEST
      results.message = model_name..' creation failed'
    else
      results.message = model_name..' created successfully'
      results.details = object:data()
    end
  end

  RESTfully.json( results )

end


function RESTfully.POST.delete( model_path, loader, load_parameter )

  local Model = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  local object
  local parameter = ngx.var['arg_'..load_parameter ]

  if parameter ~= nil then
    object = Model[loader]( Model, ngx.unescape_uri( parameter ) )
  end

  if object then
    object:delete()
    results.message = model_name..' deleted'
  else
    ngx.status = ngx.HTTP_BAD_REQUEST
    results.message = model_name..' not found'
  end

  RESTfully.json( results )

end


-- convert a string (or some table structure of strings) to the passed type
function RESTfully._string_type_convert( value, to_type, name )
  local to_type = ( to_type or '' )
  local name = ( name or '' )

  local _convert = function( val, t )
    if t:match( 'number' ) or t:match( 'integer' ) or t:match( 'rational' ) then
      if tostring( tonumber( val ) ) == val then
        return tonumber( val )
      else
        return val
      end
    elseif t:match( 'boolean' ) then
      local tester = val:lower():trim()
      if tester == 'true' or tester == 'false' or tester == '1' or tester == '0' then
        return ( tester == 'true' or tester == '1' )
      else
        return val
      end
    else
      -- unescape
      if type( val ) == 'string' then
        return ngx.unescape_uri( val )
      else
        return val
      end
    end
  end

  if type( to_type ) == 'table' then

    -- if array conversion
    if table.isarray( to_type ) then
      if #to_type == 1 then

        if type( to_type[1] ) == 'string' then
          if type( value ) == 'table' and table.isarray( value ) then
            local results = {}
            for i = 1, #value do
              results[i] = _convert( value[i], to_type[1] )
            end
            return results
          end
        elseif type( to_type[1] ) == 'table' then
          if type( value ) == 'table' and table.isarray( value ) then
            local array_result = {}
            for index, item in ipairs( value ) do
              local nsf; nsf = name..'['..(index - 1)..']'
              array_result[index] = RESTfully._string_type_convert( item, to_type[1], nsf )
            end
            return array_result
          else
            if name ~= '' then name = ' at '..name end
            error( "complex type array provided for conversion of simple data or non-array"..name )
          end
        else
          error( "invalid array type" )
        end

      else
        error( "arrays of a particular type must be represented as {'[type_string]'} or { [mapping_table] }" )
      end
    -- if complex data type conversion (non-array)
    else
      if type( value ) == 'table' then
        local inner_result = {}
        for inner_name, inner_map in pairs( to_type ) do
          --ngx.say( inspect( value ) )
          --ngx.say( 'inner_name: ', inner_name, ', inner_map.type: ', inspect( inner_map.type ), ', value[inner_name]: ', inspect( value[inner_name] ) )
          local nsf; if name ~= '' then nsf = name..'.'..inner_name else nsf = inner_name end
          inner_result[inner_name] = RESTfully._string_type_convert( value[inner_name], inner_map.type, nsf )
        end
        return inner_result
      elseif value then
        if name ~= '' then name = ' at '..name end
        error( "complex type provided for conversion of simple data"..name )
      end
    end

  -- simple
  else
    if value then
      return _convert( value, to_type )
    end
  end

end



function RESTfully._posted_name_to_value( name, value, posted )

  --ngx.say( '<hr />name: ', name, ', value: ', value )

  if name:match( '%[' ) then

    -- if needed wrap first element in square parentheses for uniformity
    -- nuts[0][items][0][it] -> [nuts][0][items][0][it]
    if name[1] ~= '%[' then
      local part, remainder
      part, remainder = name:match( '^(.-)(%[.*)$' )
      name = '['..part..']'..remainder
    end

    -- remove the array signifier [] since ngx.req.get_post_args() handles that
    -- [nuts][0][items][0][it][] -> [nuts][0][items][0][it]
    if name:match( '%[%]$' ) then
      name = name:sub( 1, -3 )
    end

    local var_sofar = posted
    local index = ''

    -- split each entry into its parts
    local indices = {}
    for index in name:gmatch( '%[(.-)%]' ) do
      table.insert( indices, index )
    end

    for count, index in ipairs( indices ) do

      -- handle array indexes
      if index:match( '^%d+$' ) then
        -- switch to array lookups and account for lua counting from 1
        index = tonumber( index ) + 1
      end

      if var_sofar[index] == nil and count < #indices then
        if type( index ) == 'number' then
          local inner = {}
          table.insert( var_sofar, inner )
          var_sofar = inner
        else
          var_sofar[index] = {}
          var_sofar = var_sofar[index]
        end
      else
        if count < #indices then
          var_sofar = var_sofar[index]
        else
          var_sofar[index] = value
        end
      end
    end

  else
    posted[name] = value
  end
end



function RESTfully.post_args_to_table( posted, mapping )

  local results = {}
  local input = posted

  -- ordered names iterator
  for name, value in opairs( input ) do
    RESTfully._posted_name_to_value( name, value, results )
  end

  if mapping then
    --RESTfully.json( mapping )
    return RESTfully._string_type_convert( results, mapping )
  else
    return results
  end

end
RESTfully.uri_args_to_table = RESTfully.post_args_to_table

--function RESTfully.uri_args_to_table( gotten, mapping )
--  return RESTfully.post_args_to_table( gotten, mapping )
--end



function RESTfully.POST.data( model_path, loader, load_parameter )

  local Model = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  local object
  local parameter = ngx.var['arg_'..load_parameter ]

  if parameter ~= nil then
    object = Model[loader]( Model, ngx.unescape_uri( parameter ) )
  end

  if object then
    -- must read the request body up front
    ngx.req.read_body()
    --ngx.say( inspect( ngx.req.get_post_args() ) )
    -- coerce types to resemble fieldMapping as closely as possible
    local posted = RESTfully.post_args_to_table( ngx.req.get_post_args(), Model.fieldMapping )

    --ngx.say( inspect( posted ) )

    local valid, errors = validate.for_update( posted, Model.fieldMapping, { zero_based_indexing = true } )

    if not valid then
      ngx.status = ngx.HTTP_BAD_REQUEST
      results.message = 'submitted '..model_name..' values are invalid'
      results.errors = errors
    else
      object:set( posted )
      results.message = model_name..' updated successfully'

      --ngx.say( '\n\n'..tostring( business_object:get( 'active' ) )..'\n\n' )
      --ngx.say( '\n\n'..inspect( business_object )..'\n\n' )


      -- reload from database to verify changes and force cache flush
      results.data = Model[loader]( Model, ngx.unescape_uri( parameter ), { reload = true } ):data()
    end
  else
    ngx.status = ngx.HTTP_BAD_REQUEST
    results.message = model_name..' not found'
  end

  RESTfully.json( results )

end


--[==[
function RESTfully.POST.data( model_path, loader, load_parameter )

  local BusinessModel = require( model_path )
  local model_name = RESTfully._generate_human_readable_model_name( model_path )

  local results = {}

  local business_object
  local parameter = ngx.var['arg_'..load_parameter ]

  if parameter ~= nil then
    business_object = BusinessModel[loader]( BusinessModel, ngx.unescape_uri( parameter ) )
  end

  if business_object then
    -- must read the request body up front
    ngx.req.read_body()
    local posted = ngx.req.get_post_args()

    local valid, errors, cleaned = validate.for_update( posted, BusinessModel.fieldMapping )

    if not valid then
      ngx.status = ngx.HTTP_BAD_REQUEST
      results.message = 'submitted '..model_name..' values are invalid'
      results.errors = errors
    else
      business_object:set( cleaned )
      results.message = model_name..' updated successfully'

      -- reload from database to verify changes and force cache flush
      results.data = BusinessModel[loader]( BusinessModel, ngx.unescape_uri( parameter ), { reload = true } ):data()
    end
  else
    ngx.status = ngx.HTTP_BAD_REQUEST
    results.message = model_name..' not found'
  end

  RESTfully.json( results )

end
--]==]

return RESTfully
