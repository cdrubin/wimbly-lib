
--local Model = require( 'models/base' )
local RedisMetaDrive = class( 'RedisMetaDrive' )--, Model )


function RedisMetaDrive.static.connection()
  local red = redis:new()

  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  return red
end


function RedisMetaDrive.static.pathParts( path )
  path = ngx.unescape_uri( path )

  local parts = path:split( '/' )
  local parent = nil
  if #parts == 0 then
    part = '/'
  else
    if #parts == 1 then
      part = parts[1]
      parent = '/'
    else
      part = table.remove( parts )
      parent = '/'..table.concat( parts, '/' )
    end
  end

  return parent, part, path
end


function RedisMetaDrive.static.partsToPath( parent, part )
  if parent:sub( -1 ) ~= '/' then
    return parent..'/'..part
  else
    return parent..part
  end
end


function RedisMetaDrive.static.pathInfo( path )
  local red = RedisMetaDrive.connection();

  if path:sub( 1, 1 ) ~= '/' then
    return false, 'paths must contain a leading /'
  end

  local id = nil
  local subfolders = {}
  local documents = {}

  local res = red:smembers( path )
  for _, item in ipairs( res ) do
    if item:starts( 'id:' ) then
      id = item:match( 'id:(.+)' )
    elseif item:starts( 'folder:' ) then
      local foldername = item:match( 'folder:(.+)' )
      table.insert( subfolders, foldername )
    elseif item:starts( 'document' ) or item:starts( 'spreadsheet' ) then
      table.insert( documents, item )
    end
  end

  if id == nil then
    return false, "id of folder '"..path.."' not found"
  end

  return true, id, subfolders, documents
end


function RedisMetaDrive.static.getPathFromFolderId( id )
  local red = RedisMetaDrive.connection();

  local value = red:get( 'folder:'..id )
  if value == nil then
    return false, "folder with id '"..id.."' not found"
  else
    return true, value
  end
end


function RedisMetaDrive.static.updateFolderLinks( oldpath, newpath )

  if oldpath:sub( 1, 1 ) ~= '/' or newpath:sub( 1, 1 ) ~= '/' then
    return false, 'paths must contain a leading /'
  end

  oldpath = ngx.unescape_uri( oldpath )
  newpath = ngx.unescape_uri( newpath )

  local red = RedisMetaDrive.connection()
  local ok, id, subfolders, documents = RedisMetaDrive.pathInfo( oldpath )

  -- confirm that folder link exists for this path
  if not ok then
    local message = "pathinfo failed for oldpath '"..oldpath.."'"
    ngx.log( ngx.ERR, message )
    return false, message
  end

  if not id then
    local message = "folder id not found for oldpath '"..oldpath.."'"
    ngx.log( ngx.ERR, message )
    return false, message
  end

  -- fix this link
  red:set( 'folder:'..id, newpath )

  -- recurse into subfolders
  for _, folder in ipairs( subfolders ) do
    RedisMetaDrive.updateFolderLinks( oldpath..'/'..folder, newpath..'/'..folder )
  end

end



--[[
function RedisMetaDrive.static.updateFolderNames( oldpath, newpath, recursing )
  local recursing = recursing or false

  if oldpath:sub( 1, 1 ) ~= '/' or newpath:sub( 1, 1 ) ~= '/' then
    return 'paths must contain a leading /'
  end

  oldpath = ngx.unescape_uri( oldpath )
  newpath = ngx.unescape_uri( newpath )


  --ngx.say( path )
  --ngx.say( oldpath )
  --ngx.say( newpath )
  --ngx.log( ngx.DEBUG, 'oldpath:'..oldpath )
  --ngx.log( ngx.DEBUG, 'newpath:'..newpath )

  local red = redis:new()

  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- current path must exist
  local res = red:exists( oldpath )
  if res ~= 1 then
    return "current path '"..oldpath.. "' does not exist"
  end

  -- get contents of old path
  local id = nil
  local subfolders = {}
  local documents = {}

  local res = red:smembers( oldpath )
  for _, item in ipairs( res ) do
    if item:starts( 'id:' ) then
      id = item:match( 'id:(.+)' )
    elseif item:starts( 'folder:' ) then
      local foldername = item:match( 'folder:(.+)' )
      table.insert( subfolders, foldername )
    elseif item:starts( 'document' ) or item:starts( 'spreadsheet' ) then
      table.insert( documents, item )
    end
  end

  if id == nil then
    return "id of folder '"..oldpath.."' not found"
  end


  -- new path must not exist (unless there are some subfolders)
  local res = red:exists( newpath )
  if res == 1 and not #subfolders > 1 then
    return "new path '"..newpath.."' already exists"
  end

  local oldparent, oldpart = RedisMetaDrive.pathParts( oldpath )
  local newparent, newpart = RedisMetaDrive.pathParts( newpath )

  -- new parent must exist (unless recursing in a subfolder)
  local res = red:exists( newparent )
  if res ~= 1 and not recursing then
    return 'new parent must already exist'
  end

  -- recurse through the subfolders and set recurse mode true
  for _, subfolder in ipairs( subfolders ) do
    RedisMetaDrive.updateFolderNames( oldpath..'/'..subfolder, newpath..'/'..subfolder, true )
  end

  -- update this folder link
  local ok, err = red:set( 'folder:'..id, newpath )
  if not ok then
    ngx.say( "problem updating link 'folder:"..id.."' from '"..oldpath.."' to '"..newpath.."'" )
    return
  end

  -- fix this folder key
  local res, err = red:renamenx( oldpath, newpath )
  if res ~= 1 and #subfolders == 0 then
    ngx.say( "failed to rename key '"..oldpath.."' to '"..newpath.."'" )
    return
  end

  -- if there were folders I can now just delete the old key
  if #subfolders > 1 then
    local res, err = red:del( oldpath )
    if res ~= 1 and #subfolders == 0 then
      ngx.say( "failed to delete key '"..oldpath.."'" )
      return
    end
  end

  -- remove from old parent
  local res = red:srem( oldparent, 'folder:'..oldpart )
  if res ~= 1 then
    ngx.say( "failed to remove folder '"..oldpart.."' from '"..oldparent.."'" )
    return
  end

  -- if recursing then new parent may not exist yet, so add it
  local res = red:exists( newparent )
  if recursing and res ~= 1 then
    RedisMetaDrive.addFolder( newparent )
  else
    local res = red:sadd( newparent, 'folder:'..newpart )
    if res ~= 1 then
      ngx.say( "failed to add folder '"..newpart.."' to '"..newparent.."'" )
      return
    end
  end

  -- add to new parent
  --local res = red:sadd( newparent, 'folder:'..newpart )
  --if res ~= 1 and then
--    ngx.say( "failed to add folder '"..newpart.."' to '"..newparent.."'" )
    --return
  --end

  return 'success', newpath

end
--]]


-- returns list of documents and folders at this path
function RedisMetaDrive.static.list( path )

  if path:sub( 1, 1 ) ~= '/' then
    return 'path must contain a leading /'
  end

  path = ngx.unescape_uri( path )
  --ngx.say( path )

  local red = redis:new()

  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- get members
  local members = red:smembers( path )

  local folders = {}
  local documents = {}

  for _, item in pairs( members ) do
    if item:starts( 'folder:' ) then
      table.insert( folders, item:sub( 8 ) )
    elseif item:starts( 'document:' ) or item:starts( 'spreadsheet:' ) then
      table.insert( documents, item )
    end
  end

  local results = {}

  -- sort folders by name
  table.sort( folders )

  for _, folder in pairs( folders ) do
    table.insert( results, { name = folder, type = 'folder' } )
  end

  -- get list of document names
  red:init_pipeline()
  for _, item in ipairs( documents ) do
    red:hget( item, 'name' )
  end

  local res, err = red:commit_pipeline()
  if not res then
    ngx.say( "failed to get the document names of the linked documents within '"..path.."'" )
    return
  end

  local named_documents = {}
  for index, name in ipairs( res ) do
    named_documents[name] = documents[index]
  end

  --ngx.say( inspect( sorted_documents ) )

  --table.sort( sorted_documents )

  --ngx.say( inspect( sorted_documents ) )

  for name, doc in opairs( named_documents ) do
    table.insert( results, { id = doc, type = 'document', name = name } )
  end

  --ngx.say( inspect( sorted_documents ) )

  return results

end

-- move item
function RedisMetaDrive.static.moveFolder( path, newpath )

  if path:sub( 1, 1 ) ~= '/' or newpath:sub( 1, 1 ) ~= '/' then
    return 'current path and new path must contain a leading /'
  end

  path = ngx.unescape_uri( path )
  newpath = ngx.unescape_uri( newpath )
  --ngx.say( path )
  --ngx.say( newpath )

  local red = redis:new()
  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- current path must exist
  local res = red:exists( path )
  if res ~= 1 then
    return 'current path does not exist'
  end

  -- new path must not exist
  local res = red:exists( newpath )
  if res == 1 then
    return 'new path already exists'
  end

  local parent, part = RedisMetaDrive.pathParts( path )
  local newparent, newpart = RedisMetaDrive.pathParts( newpath )

  -- new path parent must exist
  local res = red:exists( newparent )
  if res ~= 1 then
    return 'new path parent does not exist'
  end

  -- remove from old parent
  local removed = red:srem( parent, 'folder:'..part )
  if removed ~= 1 then
    ngx.say("failed to delete folder entry '"..part.. "' from within parent '"..parent.."' during move")
    return
  end

  -- add to new parent
  local added = red:sadd( newparent, 'folder:'..newpart )
  if added ~= 1 then
    ngx.say("failed to add folder entry '"..newpart.. "' to parent '"..newparent.."' during move")
    return
  end

  -- recursively fix folder links
  RedisMetaDrive.updateFolderLinks( path, newpath )

  -- rename actual folder
  local from = RedisMetaDrive.partsToPath( parent, part )
  local to = RedisMetaDrive.partsToPath( newparent, newpart )
  local res = red:renamenx( from, to )
  if res ~= 1 then
    ngx.say("failed to rename folder '"..from.."' to '"..to.."'")
    return
  end

  -- rename all keys that start with current path to new path
  local keys = red:keys( path..'/*' )
  --ngx.say( inspect( keys ) )
  for _, key in ipairs( keys ) do
    local newkey = key:gsub( '^'..path, newpath )
    local res = red:renamenx( key, newkey )
    if res ~= 1 then
      ngx.say("failed to rename key '"..key.."' to '"..newkey.."'")
      return
    end
    --ngx.say( key..' -> '..newkey )
  end

  return 'success', newpath

end


function RedisMetaDrive.static.renameFolder( path, name )
  local parent, part = RedisMetaDrive.pathParts( path )

  local from = RedisMetaDrive.partsToPath( parent, part )
  local to = RedisMetaDrive.partsToPath( parent, name )

  return RedisMetaDrive.moveFolder( from, to )
  --return RedisMetaDrive.updateFolderNames( from, to )
end


function RedisMetaDrive.static.delete( path )

end

-- key is a path if a folder and a google document id if a document

function RedisMetaDrive.static.addFolder( path )

  if path:sub( 1, 1 ) ~= '/' then
    return 'path must contain a leading /'
  end

  path = ngx.unescape_uri( path )

  local red = redis:new()
  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end


  local parent, part = RedisMetaDrive.pathParts( path )

  -- path must not already exist
  local res = red:exists( path )
  if res == 1 then
    return 'folder already exists'
  end

  res = red:exists( parent )
  if res ~= 1 and part ~= '/' then
    return 'parent does not exist'
  end

  -- add folder
  local id = uuid()
  ok, err = red:sadd( path, 'id:'..id )
  if not ok then
    return 'error trying to add key '..path..', '..err
  end

  -- add folder link
  ok, err = red:set( 'folder:'..id, path )
  if not ok then
    return "error trying to add folder link 'folder:"..id.."' that points to path '"..path.."', "..err
  end

  -- and add to parent if not the root itself
  if path ~= '/' then
    ok, err = red:sadd( parent, 'folder:'..part )
    if not ok then
      return 'error trying to add key '..path..', '..err
    end
  end

  return 'success'
end


function RedisMetaDrive.static.deleteFolder( path )

  if path:sub( 1, 1 ) ~= '/' then
    return 'path must contain a leading /'
  end

  path = ngx.unescape_uri( path )

  local red = redis:new()
  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- check that folder exists
  local res = red:exists( path )
  if res ~= 1 then
    return 'folder does not exist'
  end

  local contents = RedisMetaDrive.list( path )

  -- check that folder is empty
  local size = red:scard( path )
  if size ~= 1 then
    return 'folder is not empty'
  end

  local parent, part = RedisMetaDrive.pathParts( path )

  -- delete entry from within parent
  local removed = red:srem( parent, 'folder:'..part )
  if removed ~= 1 then
    ngx.say("failed to delete folder '"..part.. "' from within parent '"..parent.."'")
    return
  end

  -- get folder id and delete
  local res = red:srandmember( path )
  local link = res:match( 'id:(.+)' )
  local removed = red:del( 'folder:'..link )
  if removed ~= 1 then
    ngx.say( "failed to delete folder link 'folder:"..link.."' which should point to '"..path.. "'" )
    return
  end

  -- delete key
  local removed = red:del( path )
  if removed ~= 1 then
    ngx.say("failed to delete folder '"..path.. "'")
    return
  end

  return 'success', path, parent

end


function RedisMetaDrive.static.linkDocument( path, url )

  if path:sub( 1, 1 ) ~= '/' then
    return 'path must contain a leading /'
  end

  path = ngx.unescape_uri( path )
  url = ngx.unescape_uri( url )

  --ngx.say( path )
  --ngx.say( url )

  local red = redis:new()
  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- current path must exist
  local res = red:exists( path )
  if res ~= 1 then
    return 'path does not exist'
  end

  --ngx.say( url:match( '/spreadsheet/ccc' ) )

  -- grab docId
  local key = ''
  local match = nil
  if url:match( '/document/d/' ) then
    key = 'document:'
    match = url:match( '/document/d/([A-Za-z0-9]+)/' )
  elseif url:match( '/spreadsheet/ccc' ) then
    key = 'spreadsheet:'
    match = url:match( '/spreadsheet/ccc%?key=([A-Za-z0-9-]+)' )
  end

  if match ~= nil then
    key = key..match
  end

  --ngx.say( '=='..key..'==' )
  --ngx.exit( 200 )

  --local docId =
  --ngx.say( docId )

  -- document must not already have been linked
  local res = red:exists( key )
  if res == 1 then
    res = red:hget( key, 'folder' )
    --ngx.say( inspect( res ) )
    return "'"..key.."' is already been linked inside '"..res.."''"
  end

  --ngx.say( 'eh' )

  -- check that docId is valid
  local googledrive =  require( 'models/googledrive' )
  local info = googledrive:info( key:match( ':([A-Za-z0-9-]+)' ) )
  --ngx.say( inspect( info ) )

  -- add key
  local res = red:hset( key, 'name', info.name )
  if res ~= 1 then
    return "failed to create entry with key '"..key.."'"
  end
  -- and store folder that will contain this link for backwards reference
  local res = red:hset( key, 'folder', path )


  -- add to folder
  local res = red:sadd( path, key )
  if res ~= 1 then
    return "failed to link entry key '"..key.."' in folder '"..path.."'"
  end

  return 'success', key, path

end


function RedisMetaDrive.static.deleteDocument( key )

  local red = redis:new()
  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  -- check that key exists
  local res = red:exists( key )
  if res ~= 1 then
    return "document '"..key.."' is not linked"
  end

  -- retrieve the containing folder
  local parent = red:hget( key, 'folder' )

  ngx.say( parent )
  ngx.exit( 200 )

  -- delete entry from within parent
  local removed = red:srem( parent, key )
  if removed ~= 1 then
    ngx.say("failed to remove link '"..key.. "' from within parent '"..parent.."'")
    return
  end

  -- delete key
  local removed = red:del( key )
  if removed ~= 1 then
    ngx.say("failed to delete key '"..key.. "'")
    return
  end

  return 'success', key, parent

end



--[==[
function RedisMetaDrive.static.add( key, meta )
  --meta = meta or nil

  local red = redis:new()

  local ok, err = red:connect( "127.0.0.1", 6379 )
  if not ok then
    ngx.say("failed to connect: ", err)
    return
  end

  ok, err = red:set( key, meta )
  if not ok then
    ngx.say( "add key: ", err)
    --return
  end

  local ok, err = red:set_keepalive(0, 100)
  if not ok then
  ngx.say("failed to set keepalive: ", err)
  return
end

--]==]

--ngx.say( cjson.encode( { [ngx.var.key] = tonumber( ngx.var.value ) } ) );


--end


return RedisMetaDrive
