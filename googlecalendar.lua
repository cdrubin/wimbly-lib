
local GoogleAPI = require( 'lib/googleapi' )
local GoogleCalendar = class( 'GoogleCalendar', GoogleAPI )

GoogleCalendar.static.refresh_token = '1/ZbyHsMuvCH0_zZ4CC7bYFYQN3_gXTbMUBFT0uedR89Y'

-- used the housekeeping helper pages to generate the refresh token
-- scopes required :
--   https://www.googleapis.com/auth/calendar

-- relevant user:
--   staff-developer-calendars@readingandwritingproject.com
--   tcrwp20xx


function GoogleCalendar.static:list()
  
  local api = GoogleAPI:oauthlogin( GoogleCalendar.refresh_token )
  
  local page = function( pageToken )

    local options = {
      args = {
        maxResults = 100,
        fields = 'nextPageToken,items(summary,id)',
        q = query
      }
    }
    if pageToken and pageToken ~= '' then
      options.args.pageToken = pageToken
    end

    local res = api:oauthrequest( '/calendar/v3/users/me/calendarList', options )
    return cjson.decode( res.body )
  end

  local calendars = {}
  
  local pageToken = ''
  while pageToken ~= nil do
    local results = page( pageToken )
    
    pageToken = results.nextPageToken

    for _, item in ipairs( results.items ) do
      table.insert( calendars, item )
    end
  end

  return calendars
  
end


function GoogleCalendar.static:access( calendar_id )

  local api = GoogleAPI:oauthlogin( GoogleCalendar.refresh_token )

  local page = function( pageToken )

    local options = {
      args = {
        maxResults = 100
      }
    }
    if pageToken and pageToken ~= '' then
      options.args.pageToken = pageToken
    end

    local res = api:oauthrequest( '/calendar/v3/calendars/'..calendar_id..'/acl', options )
    return cjson.decode( res.body )
  end

  local acl = {}
  
  local pageToken = ''
  while pageToken ~= nil do
    local results = page( pageToken )
    
    pageToken = results.nextPageToken

    for _, item in ipairs( results.items ) do
      table.insert( acl, { email = item.scope.value, type = item.scope.type } )
    end
  end  
  
  return acl
  
end


function GoogleCalendar.static:share( calendar_id, email )

  local api = GoogleAPI:oauthlogin( GoogleCalendar.refresh_token )

  local rule = {
    kind = "calendar#aclRule",
    scope = { type = 'user', value = email }
  }
  
  if email == 'shared@readingandwritingproject.com' then
    rule.role = 'reader'
  else
    rule.role = 'writer'
  end
  
  local body_string = cjson.encode( rule )
  
  ngx.req.set_header( 'Content-Type', 'application/json' )
  ngx.req.set_header( 'Content-Length', body_string:len() )
  local res = api:oauthrequest( '/calendar/v3/calendars/'..calendar_id..'/acl', { method = ngx.HTTP_POST, body = body_string } )

  return res
end



function GoogleCalendar.static:unshare( calendar_id, email )

  local api = GoogleAPI:oauthlogin( GoogleCalendar.refresh_token )
  local res = api:oauthrequest( '/calendar/v3/calendars/'..calendar_id..'/acl/user:'..email, { method = ngx.HTTP_DELETE } )
              
  return res
end


return GoogleCalendar
