
local GoogleAPI = require( 'lib/googleapi' )
local GoogleDrive = class( 'GoogleDrive', GoogleAPI )

GoogleDrive.static.refresh_token = '[]'
GoogleDrive.static.resources_folderid = '[]'
--GoogleDrive.static.cache_seconds = 86400
GoogleDrive.static.cache_seconds = 3600


function GoogleDrive.static:list( query, options )
  local query = query or "'docadmin@readingandwritingproject.com' in owners and trashed = false"
  local options = options or { force_refresh = false }

  --if true then return {} end

  local red = require( 'lib/rediscache' ).connect()
  local ok, res, err

  -- check the cache unless asked not to
  if not options.force_refresh then
    -- check for content in cache

    res, err = red:get( 'googledrive_list:'..query )

    if res ~= ngx.null then
      return cjson.decode( res )
    end
  end

  local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

  local page = function( pageToken )

    local options = {
      args = {
        maxResults = 100,
        fields = 'nextPageToken,items(title,id,mimeType,thumbnailLink,labels)',
        q = query
      }
    }
    if pageToken and pageToken ~= '' then
      options.args.pageToken = pageToken
    end

    local res = api:oauthrequest( '/drive/v2/files', options )
    return cjson.decode( res.body )
  end

  local files = {}
  local folders = {}

  local pageToken = ''
  while pageToken ~= nil do
    local results = page( pageToken )

    pageToken = results.nextPageToken

    if results.items then

      for _, item in ipairs( results.items ) do
        local type = item.mimeType:match( '.*%.(.*)$' ) --'document'
        if type == 'folder' then
          table.insert( folders, { id = item.id, title = item.title, type = 'folder', mimeType = item.mimeType } )
        else
          table.insert( files, { id = item.id, title = item.title, type = 'file', mimeType = item.mimeType, thumbnail = item.thumbnailLink, trashed = item.labels.trashed } )
        end
      end

    end

  end


  table.sort( folders, function( left, right ) return left.title < right.title end )
  table.sort( files, function( left, right ) return left.title < right.title end )


  local results = {}
  -- combine folders and files
  for i, folder in ipairs( folders ) do
    results[i] = folder
  end

  for i, file in ipairs( files ) do
    results[#folders + i] = file
  end


  local cache_seconds = options.expires
  if not cache_seconds then cache_seconds = GoogleDrive.cache_seconds end

  -- !!! uncomment below to start caching list results again
  red:setex( 'googledrive_list:'..query, cache_seconds, cjson.encode( results ) )

  return results

end


function GoogleDrive.static:children( folderId, options )

  -- check for content in cache
  --local red = require( 'lib/rediscache' ).connect()
  --local ok, res, err

  --res, err = red:get( 'googledrive_folderid:'..folderId )
  --if res ~= ngx.null then
    --return cjson.decode( res )
  --else
    --local result = self:list( "'"..folderId.."' in parents" )

  -- add to cache
  --red:setex( 'googledrive_folderid:'..folderId, GoogleDrive.cache_seconds, result )

  return self:list( "'"..folderId.."' in parents and trashed = false", options )
  --return {}
end


--[==[
function GoogleDrive.static:children( folderId )

  -- check for content in cache
  local red = require( 'lib/rediscache' ).connect()
  local ok, res, err

  -- check for data in cache
  res, err = red:get( 'googledrive_folderid:'..folderId )
  if res ~= ngx.null then
    return cjson.decode( res )
  else

    local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )
    local options = {}

    local res = api:oauthrequest( '/drive/v2/files/'..folderId..'/children', options )

    -- add to cache
    red:setex( 'googledrive_folderid:'..folderId, GoogleDrive.cache_seconds, res.body )

    local json = cjson.decode( res.body )
    --local results =

    return json

  end

end
--]==]

function GoogleDrive.static:resources( path, options )
  local options = ( options or { force_refresh = false } )

  -- add leading slash
  if not path:starts( '/' ) then path = '/'..path end

  -- convert path to a folderId using cache

  --ngx.say( path )

  local folderid

  if path == '/' then
    folderid = GoogleDrive.resources_folderid
    --ngx.say( 'folderid = '..folderid..' since /' )
    --ngx.exit( ngx.OK )
  else

    -- check for folderid in cache
    local red = require( 'lib/rediscache' ).connect()
    local ok, res, err
    res, err = red:get( 'resources_path:'..path )

    if res ~= ngx.null then
      folderid = res
    else

      -- build the path cache from the root to this point
      local contents = self:resources( '/' )

      local parts
      local sofar = ''

      local parts = path:split( '/' )
      -- remove first empty name
      table.remove( parts, 1 )

      --ngx.say( inspect ( parts ) )

      for i, part in ipairs( parts ) do

        sofar = sofar..'/'..part
        --ngx.say( i ..': part"'.. part.. '" = sofar"'..sofar..'"' )

        -- find part in current level contents
        for _, item in ipairs( contents ) do
          if item.title == part then
            folderid = item.id
          end
        end

        if folderid then
          red:setex( 'resources_path:'..sofar, GoogleDrive.cache_seconds, folderid )
        else
          ngx.say( 'XXXXXXXXXX not found - do something better here!' )
          ngx.exit( ngx.OK )
        end

        contents = self:resources( sofar )

      end
    end -- if not cached


  end -- if not root path

  local results = self:children( folderid, options )
  --ngx.say( path, inspect( results ), '---\n' )
  --ngx.exit( ngx.OK )
  --local results = {}

  return results

end


function GoogleDrive.static:info( id )

  -- check for content in cache
  local red = require( 'lib/rediscache' ).connect()
  local ok, res, err

  -- check for data in cache
  res, err = red:get( 'googledrive_id:'..id )

  -- uncomment below to disable cache use
  --res = ngx.null

  if res ~= ngx.null then
    return cjson.decode( res )
  else

    local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

    local res = api:oauthrequest( '/drive/v2/files/'..id )

    local information = cjson.decode( res.body )

    --ngx.say( inspect( information ) )
    --ngx.exit( ngx.OK )

    local results = {
      name = information.title,
      created_on = information.createdDate,
      modified_on = information.modifiedDate,
      modified_by = information.lastModifyingUserName,
      webContentLink = information.webContentLink,
    }

    if information.exportLinks then
      results.url = information.exportLinks[ 'application/pdf' ]
    else
      results.url = information.downloadUrl
    end

    res, err = red:setex( 'googledrive_id:'..id, GoogleDrive.cache_seconds, cjson.encode( results ) )

    return results, api
  end

end


function GoogleDrive.static:download( docId )

  local tmpfile = 'static/tmp/'..docId..'.googledrive'
  local filename

  -- only download if we don't have it already
  local file = io.open( tmpfile, 'r' )

  if file ~= nil then
    filename = file:read( '*all' )
    file:close()
  else
    local info, api = GoogleDrive:info( docId )

    if not api then
      api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )
    end

    if info.url:match( 'spreadsheets' ) then
      local spreadsheet = require( 'lib/googlespreadsheet' ).fromKey( docId )
      --ngx.say( 'hey' )
      --ngx.say( inspect( spreadsheet ) ) --spreadsheet.worksheets )
      --ngx.exit( ngx.OK )
      info.url = info.url..'&gid=0'
    end
    --ngx.say( inspect( info ) )
    --info.url:gsub( 'spreadsheets', 'a/readingandwritingproject.com/spreadsheets' )
    local res = api:oauthrequest( info.url:gsub( '^https:/', '' ), {}, '/proxy/https' )
    --ngx.say( inspect( res ) )
    --ngx.exit( ngx.OK )

    filename = res.header['Content-Disposition']:match( 'filename="(.-)"' )

    -- write contents to name that includes actual filename
    file = io.open( tmpfile..'_'..filename, 'w' )
    file:write( res.body )
    file:close()

    -- write just filename to the docId name for lookup
    file = io.open( tmpfile, 'w' )
    file:write( filename )
    file:close()

  end

  return { filename = filename, tmpfile = tmpfile..'_'..filename }

end


function GoogleDrive.static:upload_to( parent, filename, rename_to )

  local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

  -- upload
  local file = io.open( filename, 'r' )
  local contents = file:read( '*all' )
  file:close()

  local mimetypes = require 'mimetypes'
  local content_type = mimetypes.guess( filename )

  ngx.req.set_header( 'Content-Type', content_type )
  ngx.req.set_header( 'Content-Length', contents:len() )

  local res = api:oauthrequest( '/upload/drive/v2/files?uploadType=media', { method = ngx.HTTP_POST, body = contents } )

  if res.status ~= ngx.HTTP_OK then
    return res
  end

  local res_body = cjson.decode( res.body )

  --ngx.say( inspect( res_body ) )
  --ngx.exit( ngx.OK )

  local upload_id = res_body.id


  local new_filename
  if not rename_to then
    local filename_parts = filename:split( '/' )
    new_filename = filename_parts[#filename_parts]
  else
    new_filename = rename_to
  end

  -- place in parent folder
  local body = {
    kind = 'drive#file',
    title = new_filename,
    parents = { { id = parent } }
  }

  local body_string = cjson.encode( body )
  --ngx.say( body_string )

  ngx.req.set_header( 'Content-Type', 'application/json' )
  ngx.req.set_header( 'Content-Length', body_string:len() )

  local res = api:oauthrequest( '/drive/v2/files/'..upload_id, { method = ngx.HTTP_PUT, body = body_string } )

  if res.status == ngx.HTTP_OK then
    local res_body = cjson.decode( res.body )
    return { id = res_body.id, title = res_body.title, parent = parent }
  else
    return res
  end

end


function GoogleDrive.static:link( parent, child )

  local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

  local body = {
    kind = 'drive#childReference',
    id = child
  }

  local body_string = cjson.encode( body )

  ngx.req.set_header( 'Content-Type', 'application/json' )
  ngx.req.set_header( 'Content-Length', body_string:len() )

  local res = api:oauthrequest( '/drive/v2/files/'..parent..'/children', { method = ngx.HTTP_POST, body = body_string } )

  if res.status == ngx.HTTP_OK then
    return { parent = parent, child = child }
  else
    return res
  end

end


function GoogleDrive.static:unlink( parent, child )

  local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

  local res = api:oauthrequest( '/drive/v2/files/'..parent..'/children/'..child, { method = ngx.HTTP_DELETE } )

  if res.status == 204 then
    return { parent = parent, child = child }
  else
    return res
  end

end


function GoogleDrive.static:create_subfolder( parent, name )

  local api = GoogleAPI:oauthlogin( GoogleDrive.refresh_token )

  local body = {
    title = name,
    parents = { { id = parent } },
    mimeType = 'application/vnd.google-apps.folder'
  }

  local body_string = cjson.encode( body )

  ngx.req.set_header( 'Content-Type', 'application/json' )
  ngx.req.set_header( 'Content-Length', body_string:len() )

  local res = api:oauthrequest( '/drive/v2/files/', { method = ngx.HTTP_POST, body = body_string } )

  if res.status == ngx.HTTP_OK then
    local body = cjson.decode( res.body )
    return { id = body.id, title = body.title }
  else
    return res
  end

end


return GoogleDrive
