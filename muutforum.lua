
--local Model = require( 'models/base' )
local MuutForum = class( 'MuutForum' ) --, Model )

MuutForum.static.key = '[]'
MuutForum.static.secret = '[]'

function MuutForum.sso( personid, name, email, is_admin )
  local is_admin = is_admin or false

  local results = {
    key = MuutForum.static.key,
    timestamp = ngx.time()
  }

  results.fields = {
    user = {
      id = personid,
      displayname = name,
      email = email,
      is_admin = is_admin
    }
  }

  results.message = ngx.encode_base64( cjson.encode( results.fields ) )

  local str = require ('resty.string')

  results.signature = str.to_hex( ngx.sha1_bin(
    MuutForum.static.secret..' '..results.message..' '..results.timestamp
  ) )

  return results
end


return MuutForum
