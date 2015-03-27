local wimbly = {}

function wimbly.find( path, filter )
  local filter = filter or '.*'

  local directories, results = {}, {}
  for item in lfs.dir( path ) do

    local attr = lfs.attributes( path..'/'..item )

    if attr.mode == "directory" and not ( item == '.' or item == '..' ) then
      table.insert( directories, item )
    elseif attr.mode == 'file' and item:match( filter ) then
      table.insert( results, path..'/'..item )
    end
  end

  if #directories > 0 then
    for _, subdirectory in ipairs( directories ) do
      local subresults = wimbly.find( path..'/'..subdirectory, filter )
      for _, subitem in ipairs( subresults ) do table.insert( results, subitem ) end
    end
  end

  return results
end


function wimbly.preprocess( path, replacements, options )
  local options = ( options or {} )

  local lfs = require "lfs"

  local confs = wimbly.find( path, '%.conf%.source$' )

  if ngx then ngx.log( ngx.DEBUG, 'wimbly preprocessing...' ) end

  for _, source in ipairs( confs ) do
    -- load contents
    local f = io.open( source, 'r' )
    local conf_source = f:read( '*all' )
    f:close()

    local conf = conf_source:interpolate( replacements ) --original, replacement )

    if replacements['/'] then
      local pattern = '(location)%s+([%^~=]-%s-)(^?)/'
      local prefixed = '%1 %2%3'..replacements['/']
      conf = conf:gsub( pattern, prefixed )
    end

    -- write changes
    local f = io.open( source:gsub( '.source$', '' ), 'w' )

    if f then
      f:write( conf )
      f:close()
    end

  end

end


function wimbly.runtime_error()
  local runtime = "Hello" + 5
end


wimbly.error_plain = [[
---
           _           _     _
          (_)         | |   | |
 __      ___ _ __ ___ | |__ | |_   _
 \ \ /\ / / | '_ ` _ \| '_ \| | | | |
  \ V  V /| | | | | | | |_) | | |_| |
   \_/\_/ |_|_| |_| |_|_.__/|_|\__, |
                                __/ |
                 %(errortype)s error |___/

 %(location)s

 "%(message)s"

 %(filename)s

%(lines)s

---
]]


wimbly.error_html = string.interpolate( [[
<br />
<div id="wimbly_error" style="font-family: colour: black; background-color: white; padding: 0px; margin: 0px">
<pre><tt>
%(errortext)s
</tt></pre>
</div>
]], { errortext = wimbly.error_plain } )


function wimbly._source_extract( fileorcontent, linenumber, options )
  local options = options or {}
  options.indent = ( options.indent or 0 )
  options.surround = ( options.surround or 2 )
  options.padding = ( options.padding or 6 )
  options.offset = ( options.offset or 0 )

  local content = ''

  -- if fileorcontent start with a slash then treat as filename
  if fileorcontent:starts( '/' ) then
    local content_file = io.open( fileorcontent, 'r' )
    if content_file then
      content = content_file:read( '*all' )
      content_file:close()
    else
      content = ( fileorcontent..' not found\n' ):rep( linenumber + options.surround )
    end
  else
    content = fileorcontent
  end

  local content_lines = content:split( '\n' )

  local relevant_lines = {}
  local start = 1

  if linenumber > options.surround + 1 then start = linenumber - options.surround end

  for i = start, linenumber + options.surround do
    local line = ( ' ' ):rep( options.indent )
    local snumber = tostring( i + options.offset )
    if i ~= linenumber then --and indicator ~= ' ' then
      line = line..snumber:padleft( ' ', options.padding )
    else
      line = line..'> '..snumber:padleft( ' ', options.padding - 2 )
    end
    line = line..'| '..( content_lines[i] or '' )
    table.insert( relevant_lines, line )
  end

  --ngx.say( '++++\n', table.concat( error_lines, '\n' ), '\n+++' )

  return table.concat( relevant_lines, '\n' )
end


function wimbly.wrap( content, file, location, linenumber, options )
  local options = ( options or { hide_lines = false, override_message = nil } )

  local result = {}
  result.filename = file
  result.location = location
  result.linenumber = linenumber
  result.callstack = {}

  local errortype = 'runtime'

  local func, message = loadstring( content )

  local callback = function( err )
    result.traceback = debug.traceback()

    local lfs = require 'lfs'
    local cwd = lfs.currentdir()

    for func, file, line in result.traceback:gmatch( "in function '(.-)'%s*(.-):(%d*):" ) do
      if not file:starts( '/' ) then file = cwd..'/'..file end
      table.insert( result.callstack, { func = func, file = file, line = tonumber( line ) } )
    end
    result.message = err
  end

  local res
  if func then
    res = xpcall( func, callback )

    message = result.message
    --ngx.say( '======', message, '======' )
  else
    res, message = false, message
    errortype = 'compile'
  end

  if not res then
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR

    local output = wimbly.error_plain

    if ngx.headers_sent then
      if ngx.header.content_type == 'text/html' then
        output = wimbly.error_html
      end
    else
      ngx.header.content_type = 'text/plain'
    end

    local offset, error_message
    --ngx.say( inspect( result ) )
    if type( message ) == 'string' then
      offset, error_message = message:match( '%]:(%d+): (.*)$' )
      if not error_message then
        error_message = inspect( message )
      end
    --elseif type( message ) == 'table' then
      --error_message = inspect( message )
    else
      result.callstack = {}
      options.hide_extract = true
      options.override_message = inspect( result.message )
      --ngx.say( inspect( resmessage ) )
    end


    if offset then
      offset = tonumber( offset )
    else
      offset = 0
      --error_message = ''
    end

    local extract = ''

    if #result.callstack > 3 then
      -- add line number from level 2
      file = file..':'..result.callstack[#result.callstack - 2].line
      for i = #result.callstack - 3, 1, -1 do
        file = file..'\n'..( ' ' ):rep( ( #result.callstack - i ) * 2 -1 )..result.callstack[i].file..':'..result.callstack[i].line
      end
      error_message = error_message:match( ':%d+:%s(.*)$' )
      extract = wimbly._source_extract( result.callstack[1].file, result.callstack[1].line, { indent = 1 } )
    else
      file = file..':'..offset + linenumber
      extract = wimbly._source_extract( content, offset, { offset = linenumber, indent = 1 } )
    end

    if options.hide_extract then extract = '' end
    if options.override_message then error_message = options.override_message end

    ngx.say( output:interpolate( { errortype = errortype, message = error_message, calls = calls, filename = file, location = location, lines = extract } ) )
    ngx.exit( ngx.OK )
  end
end


function wimbly.wrap_load( filename, file, location, linenumber )

  local content_file = io.open( filename, 'r' )
  if not content_file then
    return wimbly.wrap( string.interpolate( [[
      local content_file = io.open( '%(filename)s', 'r' )
      local content = content_file:read( '*all' )
      ]], { filename = filename } ), file, location, linenumber, { hide_extract = true, override_message = filename..' not found' } )
  end

  local content = content_file:read( '*all' )
  content_file:close()

  --ngx.say( '++++'..content..'++++' )

  return wimbly.wrap( content, file..':'..linenumber..'\n   '..filename, location, 0 )
end


function wimbly._debug_location_conf( file, location, conf, linenumberoffset )
  local conf_lines = conf:split( '\n' )

  local _by_lua_pattern = "_by_lua%s*'(.-[^\\])'"
  local _by_lua_offsets = {}
  local _by_lua_file_pattern = "_by_lua_file%s*'(.-[^\\])'"
  local _by_lua_file_offsets = {}

  for i = 1, #conf_lines do
    if conf_lines[i]:match( "_by_lua%s*'" ) then table.insert( _by_lua_offsets, linenumberoffset + i ) end
    if conf_lines[i]:match( "_by_lua_file%s*'" ) then table.insert( _by_lua_file_offsets, linenumberoffset + i - 1 ) end
  end

  --ngx.log( ngx.DEBUG, inspect( _by_lua_offsets ) )
  --ngx.log( ngx.DEBUG, _by_lua_file_offsets )


  local _by_lua_replacement = "_by_lua 'wimbly.wrap( [======[%1]======], \""..file.."\", \""..location.."\", %%(byluaoffset)d )'"
  conf = conf:gsub( _by_lua_pattern, _by_lua_replacement )

  local _by_lua_file_replacement = "_by_lua 'wimbly.wrap_load( \"%1\", \""..file.."\", \""..location.."\", %%(byluafileoffset)d )'"
  conf = conf:gsub( _by_lua_file_pattern, _by_lua_file_replacement )

  -- now fix all the offsets
  conf_lines = conf:split( '\n' )
  local _by_lua_index = 1
  local _by_lua_file_index = 1
  for i, conf_line in ipairs( conf_lines ) do
    if conf_line:match( 'byluaoffset' ) then
      --ngx.log( ngx.DEBUG, '_by_lua_index', _by_lua_index )
      conf_lines[i] = conf_lines[i]:interpolate( { byluaoffset = _by_lua_offsets[_by_lua_index] } )
      _by_lua_index = _by_lua_index + 1
    elseif conf_line:match( 'byluafileoffset' ) then
      conf_lines[i] = conf_lines[i]:interpolate( { byluafileoffset = _by_lua_file_offsets[_by_lua_file_index] } )
      _by_lua_file_index = _by_lua_file_index + 1
    end
  end

  return table.concat( conf_lines, '\n' ), #conf_lines
end


function wimbly.debug( path )
  local options = ( options or {} )

  local lfs = require "lfs"

  local confs = wimbly.find( path, 'urls%.conf$' )

  if ngx then ngx.log( ngx.DEBUG, 'wimbly debug rewriting...' ) end

  for _, source in ipairs( confs ) do
    -- load contents
    local f = io.open( source, 'r' )
    local conf = f:read( '*all' )
    f:close()

    local conf_lines = conf:split( '\n' )
    local out_lines = {}

    if true then
    --if source:match( 'file/urls.conf' ) then
      --ngx.log( ngx.DEBUG, source )

      local linenumber = 1
      while linenumber < #conf_lines do
        local line = conf_lines[linenumber]
        -- only match lines that start with 'location'
        local location = line:match( "location%s*.%s*(.-)%s*'" )
        location = line:match( "^location%s*.%s*(.-)%s" )

        -- if a location starts here
        if location then
          --ngx.log( ngx.DEBUG, location )

          local forward_conf_lines = table.slice( conf_lines, linenumber )
          --ngx.log( ngx.DEBUG, inspect( forward_conf_lines ) )
          local forward_conf = table.concat( forward_conf_lines, '\n' )
          -- assuming that the '{' is on location line
          local out_location, directives = forward_conf:match( '(location%s*.%s*.-) (%b{})' )

          --ngx.log( ngx.DEBUG, location, ' ----> ', directives )

          local debug_conf, lines_processed

          -- comment following line later
          --debug_conf, lines_processed = 'OUT', 1
          debug_conf, lines_processed = directives, #directives:split( '\n' )

          --if location:match( '/_file/error.' ) then
            debug_conf, lines_processed = wimbly._debug_location_conf( source, location, directives, linenumber )
          --end

          --ngx.log( ngx.DEBUG, ' === ', out_location..' '..debug_conf )

          --linenumber = linenumber + 1
          linenumber = linenumber + lines_processed
          table.insert( out_lines, out_location..' '..debug_conf )
        else
          linenumber = linenumber + 1
          table.insert( out_lines, line )
        end

      end

      conf = table.concat( out_lines, '\n' )

    end -- allows only work on file/urls.conf for debugging

    --ngx.log( ngx.DEBUG, table.concat( out_lines, '\n' ) )

    --conf = table.concat( out_lines, '\n' )

    -- write changes
    local f = io.open( source, 'w' )

    if f then
      f:write( conf )
      f:close()
    end

  end
end

--wimbly.preprocess( '/var/www/application/connect.readingandwritingproject.com', { ['app'] = '../../application/connect.readingandwritingproject.com' } )

return wimbly
