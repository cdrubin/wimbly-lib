
--local Model = require( 'models/base' )
local BigBlueButton = class( 'BigBlueButton' )


BigBlueButton.static.salt = '[]'
BigBlueButton.static.endpoint = '/proxy/bigbluebutton/api'


function BigBlueButton.static.call( call, parameters, options )
  local parameters = parameters or {}
  local options = options or {}

  ngx.log( ngx.DEBUG, inspect( parameters ) )

  local query = ngx.encode_args( parameters )
  local checksum_query = call..query..BigBlueButton.salt

  local str = require ('resty.string')
  local checksum = str.to_hex( ngx.sha1_bin( checksum_query ) )

  query = query..'&checksum='..checksum

  local url = BigBlueButton.endpoint..'/'..call..'?'..query

  ngx.log( ngx.DEBUG, url )

  if options.url then
    return url:gsub( '^/proxy', '' )
  else

    local res

    -- change to post if options post is set
    if options.post then
      local body = [[
<?xml version="1.0" encoding="UTF-8"?>
<modules>
  <module name="presentation">
    <document url="http://connect.readingandwritingproject.com/connect.pdf" />
  </module>
</modules>
]]
      res = ngx.location.capture( url, { body = body, method = ngx.HTTP_POST } )
    else
      res = ngx.location.capture( url )
    end

    --ngx.say( inspect( res ) )
    --ngx.exit( ngx.OK )

    local results = {}
    local results_pointer = results
    local results_pointer_stack = {}
    local key_name_stack = {}
    local key = ''

    local sax = slaxml:parser{
      startElement = function( name, nsURI )
        --ngx.log( ngx.DEBUG, 'startElement: '..name.. ', '..(nsURI or '') )
        --ngx.log( ngx.DEBUG, inspect( results ) )
        if name ~= 'response' then
          --ngx.log( ngx.DEBUG, ' - '..name )
          key = name:lower()

          local parent_key = key_name_stack[#key_name_stack]
          if parent_key == key..'s' then
            local element = {}
            table.insert( results_pointer, element )
            table.insert( results_pointer_stack, results_pointer )
            results_pointer = element
          else
            if type( results_pointer[key] ) ~= 'table' then
              ngx.log( ngx.DEBUG, ' x not table yet' )
              results_pointer[key] = {}
            end

            table.insert( results_pointer_stack, results_pointer )
            results_pointer = results_pointer[key]
          end

          table.insert( key_name_stack, key )

        end
      end,
      closeElement = function( name, nsURI )
        --ngx.log( ngx.DEBUG, 'closeElement: '..name.. ', '..(nsURI or '') )
        --ngx.log( ngx.DEBUG, inspect( results ) )
        results_pointer = table.remove( results_pointer_stack )
        table.remove( key_name_stack )
      end,
      text = function(text)
        if key ~= '' then
          if results_pointer ~= nil then
            --table.insert( results_pointer, text )
            results_pointer_stack[#results_pointer_stack][key_name_stack[#key_name_stack]] = text
          end
        end
      end
    }

    sax:parse( res.body, { stripWhitespace = true } )
    --ngx.say( inspect( results ) )
    --ngx.exit( ngx.OK )

    return results
  end
end

function BigBlueButton.static.create( meetingid, moderatorpassword, attendeepassword )
  return BigBlueButton.call( 'create', { meetingID = meetingid, moderatorPW = moderatorpassword, attendeePW = attendeepassword, logoutURL = 'http://readingandwritingproject.org/member', record = 'true' }, { post = true } )
end

function BigBlueButton.static.running( meetingid )
  local res = BigBlueButton.call( 'isMeetingRunning', { meetingID = meetingid } )
  return res.running == 'true'
end

function BigBlueButton.static.joinurl( meetingid, name, password )
  return BigBlueButton.call( 'join', { meetingID = meetingid, fullName = name, password = password }, { url = true } )
end

function BigBlueButton.static.list( meetingid, name, password )
  return BigBlueButton.call( 'getMeetings' )
end

function BigBlueButton.static.info( meetingid, password )
  return BigBlueButton.call( 'getMeetingInfo', { meetingID = meetingid, password = password } )
end

function BigBlueButton.static.terminate( meetingid, password )
  return BigBlueButton.call( 'end', { meetingID = meetingid, password = password } )
end

function BigBlueButton.static.recordings( meetingid )
  local results = BigBlueButton.call( 'getRecordings', { meetingID = meetingid } )

  for _, recording in ipairs( results.recordings ) do
    recording.startdate = date( tonumber( recording.starttime / 1000 ) ):fmt( '%F %T' )
    recording.enddate = date( tonumber( recording.endtime / 1000 ) ):fmt( '%F %T' )
  end

  return results.recordings
  --return BigBlueButton.call( 'getRecordings', { meetingID = meetingid } )
end

return BigBlueButton
