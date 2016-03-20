
--local Model = require( 'models/base' )
local GoogleAPI = class( 'GoogleAPI' )


GoogleAPI.static.clientid = '[]'
GoogleAPI.static.clientemail = '[]'
GoogleAPI.static.clientsecret = '[]'
GoogleAPI.static.redirecturi = '[]';


-- docadmin@readingandwritingproject.com
-- D0csad1M


-- client login uses an email and password to get access to old APIs
function GoogleAPI.static.clientlogin( service, email, password )
  local email = email or '[]'
  local password = password or '[]'

  local args = {
    Email = email,
    Passwd = password,
    service = service
  }

  local res = ngx.location.capture( '/proxy/google/accounts/ClientLogin?'..ngx.encode_args( args ) )

  if ( res.status == 200 ) then
    local auth = res.body:match( 'Auth=([%d%a-_]+)' )
    if auth == nil then
      error( 'google client login authentication failure', 2 )
    else
      return auth
    end
  end
end


function GoogleAPI.static.oauth2()
  local options = {
    client_id = GoogleAPI.clientid,
    client_secret = GoogleAPI.clientsecret,
    refresh_token = this.refreshtoken,
    grant_type = 'refresh_token'
  }

  ngx.req.set_header( 'Content-Type', 'application/x-www-form-urlencoded' )
  local res = ngx.location.capture( '/proxy/googleaccounts/o/oauth2/token', { method = ngx.HTTP_POST, body = ngx.encode_args( options ) } )

  if ( res.status == 200 ) then
    local auth = res.body:match( '"access_token" : "([%d%a%.-_]+)"' )
    if auth == nil then
      error( 'google oauth2 login authentication failure', 2 )
    else
      local api = this:new()
      api.access_token = auth
      return api
    end
  end

end


-- oauth2 login takes a previously granted refresh token and retrieves a new access token
function GoogleAPI.static:oauthlogin( refreshtoken )
  local options = {
    client_id = GoogleAPI.clientid,
    client_secret = GoogleAPI.clientsecret,
    refresh_token = refreshtoken,
    grant_type = 'refresh_token'
  }

  ngx.req.set_header( 'Content-Type', 'application/x-www-form-urlencoded' )
  local res = ngx.location.capture( '/proxy/googleaccounts/o/oauth2/token', { method = ngx.HTTP_POST, body = ngx.encode_args( options ) } )

  if ( res.status == 200 ) then
    local auth = res.body:match( '"access_token" : "([%d%a%.-_]+)"' )
    if auth == nil then
      error( 'google oauth2 login authentication failure', 2 )
    else
      local api = GoogleAPI:new()
      api.access_token = auth
      return api
    end
  end

end



function GoogleAPI:oauthrequest( endpoint, options, proxy )
  local proxy = proxy or '/proxy/googleapi'
  local options = options or {}

  if self.access_token == nil then
    error( 'oauthlogin needs to be called before requests can be made' )
  end
  ngx.req.set_header( 'Authorization', 'Bearer '..self.access_token )

  --ngx.say( 'endpoint: ', endpoint, ', proxy: ', proxy )

  local res = ngx.location.capture( proxy..endpoint, options )
  return res
end

--[[
TODO : implement a generic paging call that calls a collector function on
       each page of results that are returned. New lua book had info on
       collection

function GoogleAPI:oauthrequestall( endpoint, options, collector )

  local page = function( pageToken )
    if pageToken and pageToken ~= '' then
      options.args.pageToken = pageToken
    end

    local res = self:oauthrequest( endpoint, options )
    return cjson.decode( res.body )
  end


  local pageToken = ''
  while pageToken ~= nil do
    local results = page( pageToken )
    pageToken = results.nextPageToken
    local acculated = collector( results )
  end

end

--]]

return GoogleAPI
