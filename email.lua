
local email = {
  client = 'wimbly'
}

function email.send( options )
  options.cc = options.cc or {}
  options.bcc = options.bcc or {}
  options.attachments = options.attachments or {}

  local sock = ngx.socket.tcp()
  sock:settimeout( 5000 )

  local ok, err = sock:connect( '127.0.0.1', 25 )
  if not ok then ngx.say( 'failed to connect to smtp port: ', err ) return end

  -- mime boundary
  local boundary = 'boundary'..ngx.md5( ngx.time() )..'boundary'

  -- private function for smtp protocol exchange
  function _exchange( text, pattern, echo )
    local echo = echo or false

    if text then
      local bytes, err = sock:send( text..'\r\n' )
      if not bytes then ngx.say( 'failed to transmit: ', err ) end
      if echo then ngx.say( 'C: '..text ) end
    end

    local reader = sock:receiveuntil( '\r\n' )

    local data, err, partial = reader( 4096 )
    if not data or err then ngx.say( 'failed to read response: ', err ) end

    if pattern and not data:find( pattern ) then ngx.say( 'unexpected return value: ', data ) end

    if echo then ngx.say( 'S: '..data ) end
    return data
  end

  -- private function for attaching a file
  local function _attachment( name, filename )
    local headers = 'Content-Transfer-Encoding: base64\r\n'

    local f = io.open( filename, 'rb' )
    local content = f:read( '*all' )
    f:close()

    if name:lower():ends( '.pdf' ) then headers = 'Content-Type: application/pdf; name='..name..'\r\n'..headers end

    headers = headers..'Content-Disposition: attachment; filename='..name

    local encoded = ngx.encode_base64( content )
    local broken_encoded = {}

    local chunk_size = 60
    local parts = math.ceil( #encoded / chunk_size )

    for part = 1, parts do
      broken_encoded[part] = encoded:sub( (part - 1) * chunk_size + 1, part * chunk_size )
    end

    local broken_encoded_string = table.concat( broken_encoded, '\r\n' )

    return string.format( [[
--%s
%s

%s
]], boundary, headers, broken_encoded_string )

  end

  -- consume connection message
  local response = _exchange()

  -- consume welcome message
  _exchange( 'HELO '..email.client )

  -- handle from
  _exchange( 'MAIL FROM:<'..options.from.email..'>', '250 %d.%d.%d Ok' )

  -- handle to, cc and bcc
  for _, person in ipairs( options.to ) do _exchange( 'RCPT TO:<'..person.email..'>', '250 %d.%d.%d Ok' ) end
  for _, person in ipairs( options.cc ) do _exchange( 'RCPT TO:<'..person.email..'>', '250 %d.%d.%d Ok' ) end
  for _, person in ipairs( options.bcc ) do _exchange( 'RCPT TO:<'..person.email..'>', '250 %d.%d.%d Ok' ) end

  -- prepare attachments
  local attachments_encoded = ''
  for _, attachment in ipairs( options.attachments ) do
    attachments_encoded = attachments_encoded.._attachment( attachment.name, attachment.filename )
  end

  -- prepare to send message data
  _exchange( 'DATA', '354 End data with' )

  local to_list = ''
  for _, person in ipairs( options.to ) do to_list = to_list..'"'..person.name..'" <'..person.email..'>, ' end
  to_list = to_list:sub( 1, -3 )

  local cc_list = ''
  for _, person in ipairs( options.cc ) do cc_list = cc_list..'"'..person.name..'" <'..person.email..'>, ' end
  cc_list = cc_list:sub( 1, -3 )

  --local bcc_list = ''
  --for _, person in ipairs( options.bcc ) do bcc_list = bcc_list..'"'..person.name..'" <'..person.email..'>, ' end
  --bcc_list = bcc_list:sub( 1, -3 )


  local data = string.interpolate( [[
From: "%(fromname)s" <%(fromemail)s>
To: %(tolist)s
Cc: %(cclist)s
Subject: %(subject)s
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="%(boundary)s"

--%(boundary)s
Content-Type: text/plain

%(body)s

%(attachments)s--%(boundary)s--
.]], {
       fromname = options.from.name, fromemail = options.from.email,
       tolist = to_list, cclist = cc_list, bcclist = bcc_list,
       subject = options.subject, boundary = boundary, body = options.body, attachments = attachments_encoded
     }
  )

  return _exchange( data, '250 %d.%d.%d Ok' )

end


return email
