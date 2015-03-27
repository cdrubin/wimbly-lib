local GoogleAPI = require( 'lib/googleapi' )
local GoogleAdmin = class( 'GoogleAdmin', GoogleAPI )

-- used the housekeeping helper pages to generate the refresh token
-- scopes required :
--   https://www.googleapis.com/auth/admin.directory.group
GoogleAdmin.static.refresh_token = '1/Jra0-Iy8tplAo4uG0q-axb_MuqSrrYTZJhFgE_CXwlA'

-- use https://developers.google.com/admin-sdk/
function GoogleAdmin.static.groupMembership( groupemail )

  local api = GoogleAPI:oauthlogin( GoogleAdmin.refresh_token )
  local res = api:oauthrequest( '/admin/directory/v1/groups/'..groupemail..'/members' )

  --ngx.say( res.body )

  local response = cjson.decode( res.body )

  local result = {}

  for _, member in ipairs( response.members ) do
    table.insert( result, { email = member.email, id = member.id } )
  end

  return result


end

return GoogleAdmin
