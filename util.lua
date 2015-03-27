-- string convenience methods

-- starts with?
function string.starts(String,Start)
  return string.sub(String,1,string.len(Start))==Start
end

-- ends with?
function string.ends(String,End)
  return End=='' or string.sub(String,-string.len(End))==End
end

-- trim whitespace
function string.trim(String)
  return String:match("^%s*(.-)%s*$")
end

-- split with pattern
function string.split(str, pat )
  pat = pat or " "
  local t = {} -- NOTE: use {n = 0} in Lua-5.0
  local fpat = "(.-)" .. pat
  local last_end = 1
  local s, e, cap = str:find( fpat, 1 )
  while s do
    table.insert( t,cap )
    last_end = e + 1
    s, e, cap = str:find( fpat, last_end )
  end
    cap = str:sub( last_end )
    table.insert( t, cap )
  return t
end

-- interpolatation by name substitution
function string.interpolate( s, tab )
  local _format = function(k, fmt)
    return tab[k] and ("%"..fmt):format( tab[k] ) or '%('..k..')'..fmt
  end

  return ( s:gsub( '%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])', _format ) )
end

-- padright
function string.padright( str, s, length )
  local s = s or ' '
  local length = length or str:len()

  local n = math.floor( ( length - #str ) / #s )
  local t = { str }
  for i = 2, n + 1 do
    t[i] = s
  end
  return table.concat( t )
end

-- padleft
function string.padleft( str, s, length )
  local s = s or ' '
  local length = length or str:len()

  local n = math.floor( ( length - #str ) / #s )
  local t = { }
  for i = 1, n do
    t[i] = s
  end
  t[#t+1] = str
  return table.concat( t )
end


-- ordered table iterator
function opairs( t, order )
  -- collect the keys
  local keys = {}
  for k in pairs( t ) do keys[#keys+1] = k end

  -- if order function given, sort by it by passing the table and keys a, b,
  -- otherwise just sort the keys
  if order then
    table.sort( keys, function( a, b ) return order( t, a, b ) end )
  else
    table.sort( keys )
  end

  -- return the iterator function
  local i = 0
  return function()
    i = i + 1
    if keys[i] then
      return keys[i], t[keys[i]]
    end
  end
end

-- multi-arguments as table
function table.pack(...)
  return { n = select("#", ...), ... }
end


function table.copy( original )
  local original_type = type( original )
  local copy
  if original_type == 'table' then
    copy = {}
    for original_key, original_value in next, original, nil do
      copy[table.copy( original_key ) ] = table.copy( original_value )
    end
    -- use the same metatable (do not copy that too)
    setmetatable( copy, getmetatable( original ) )
  else -- number, string, boolean, etc
    copy = original
  end
  return copy
end


-- return table keys as an array
function table.keys( t, quotes )
  local quotes = quotes or ''

  local keys = {}
  local i = 1
  for key, value in pairs( t ) do
    keys[i] = quotes..key..quotes
    i = i + 1
  end

  return keys
end



function table.dotget( t, path )

  local parts = path:split( '%.' )
  local node = t

  for level, part in ipairs( parts ) do
    if node == nil then return nil end

    local index
    -- if part contains a number index
    if part:match( '.+%[%d+%]$' ) then
      part, index = part:match( '(.+)%[(%d+)%]' )
      index = tonumber( index )
    end

    if level < #parts then
      if index then
        node = node[part][index]
      else
        node = node[part]
      end
    elseif level == #parts then
      if index then
        return node[part][index]
      else
        return node[part]
      end
    end
  end

end


function table.dotset( t, path, value )

  local parts = path:split( '%.' )
  local node = t

  for level, part in ipairs( parts ) do

    local index
    -- if part contains a number index
    if part:match( '.+%[%d+%]$' ) then
      part, index = part:match( '(.+)%[(%d+)%]' )
      index = tonumber( index )
    end

    if level < #parts then
      if node[part] == nil then node[part] = {} end
      if index then
        if node[part][index] == nil then node[part][index] = {} end
        node = node[part][index]
      else
        node = node[part]
      end
    elseif level == #parts then
      if index then
        if node[part] == nil then node[part] = {} end
        node[part][index] = value
      else
        node[part] = value
      end
    end
  end

  return value

end


function table.indexof( t, value )
  for index, element in pairs( t ) do
    if value == element then
      return index
    end
  end
end


-- only contiguous integer indices starting at 1 constitute an array
function table.isarray( t )
  local max = 0
  local count = 0

  for key, value in pairs( t ) do
    if type( key ) == 'number' then
      if key > max then max = key end
      count = count + 1
    else
      return false
    end
  end

  if max ~= count then
    return false
  else
    return max
  end

end


function table.slice( t, i1, i2 )
  local res = {}
  local n = #t

  -- default values for range
  i1 = i1 or 1
  i2 = i2 or n

  if i2 < 0 then
    i2 = n + i2 + 1
  elseif i2 > n then
    i2 = n
  end

  if i1 < 1 or i1 > n then
    return {}
  end

  local k = 1
  for i = i1, i2 do
    res[k] = t[i]
    k = k + 1
  end
  return res
end


function table.tocsv( t )
  local str = ''

  for _, item in pairs( t ) do
    if type( item ) ~= 'table' then
      item = tostring( item )
      if item:find( '[,"]' ) then
        item = '"'..item:gsub( '"', '""' )..'"'
      end
      str = str..','..item
    end
  end

  return str:sub( 2 ) -- remove first comma
end


function table.indexby( t, key_name )
  local result = {}

  for _, element in ipairs( t ) do
    result[ element[ key_name ] ] = element
  end

  return result
end


function table.difference( from, take )
  local result_lookup = {}
  for _, element in ipairs( from ) do result_lookup[element] = true end
  for _, element in ipairs( take ) do result_lookup[element] = nil end

  local result = {}
  local index = 1
  for _, item in ipairs( from ) do
    if result_lookup[item] then
      result[index] = item
      index = index + 1
    end
  end

  return result
end


function table.intersection( a, b )
  local lookup_b = {}
  for _, element in ipairs( b ) do lookup_b[element] = true end

  local result = {}
  local index = 1
  for _, item in ipairs( a ) do
    if lookup_b[ item ] then
      result[index] = item
      index = index + 1
    end
  end

  return result
end
