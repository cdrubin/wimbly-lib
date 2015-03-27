
local GoogleAPI = require( 'lib/googleapi' )
local GoogleSpreadsheet = class( 'GoogleSpreadsheet', GoogleAPI )

-- used the housekeeping helper pages to generate the refresh token
-- scopes required :
--   https://spreadsheets.google.com/feeds
--   https://docs.google.com/feeds
GoogleSpreadsheet.static.refresh_token = '1/BF2G_V-O_tF0nSVlbIbf98COhkrTUeCE0LH8eR8mrhM'
GoogleSpreadsheet.static.api_proxy = '/proxy/googlespreadsheets'

GoogleSpreadsheet.key = nil
GoogleSpreadsheet.worksheets = {}

function GoogleSpreadsheet.static.list()

  local api = GoogleAPI:oauthlogin( GoogleSpreadsheet.refresh_token )
  local res = api:oauthrequest( '/feeds/spreadsheets/private/full', nil, GoogleSpreadsheet.api_proxy )

  local spreadsheets = {}
  for id, title in res.body:gmatch( "<entry>.-<id>https://spreadsheets.google.com/feeds/spreadsheets/private/full/(.-)</id>.-<title type='text'>(.-)</title>.-</entry>") do
    table.insert( spreadsheets, { id = id, title = title } )
  end

  return spreadsheets
end


function GoogleSpreadsheet.static.fromKey( key )
  if key == nil then error( 'no spreadsheet key specified', 2 ) end

  local api = GoogleAPI:oauthlogin( GoogleSpreadsheet.refresh_token )

  local spreadsheet = GoogleSpreadsheet:new()
  spreadsheet.key = key

  local res = api:oauthrequest( '/drive/v2/files/'..spreadsheet.key, nil )
  local info = cjson.decode( res.body )
  spreadsheet.title = info.title
  spreadsheet.created = info.createdDate
  spreadsheet.modified = info.modifiedDate
  --ngx.say( res.body )

  --ngx.say( '==================' )
  spreadsheet.worksheets = {}

  local res = api:oauthrequest( '/feeds/worksheets/'..spreadsheet.key..'/private/full', nil, GoogleSpreadsheet.api_proxy )
  --ngx.say( res.body )
  --ngx.say( '---' )
  
  --for key, id, title, rows, columns in res.body:gmatch( "<entry>.-<id>https://spreadsheets.google.com/feeds/worksheets/(.-)/private/full/(.-)<.-<title type=.text.>(.-)</title>.-rowCount>(%d+).-colCount>(%d+).-</entry>") do
  for key, id, title, rows, columns in res.body:gmatch( "<entry>.-<id>https://spreadsheets.google.com/feeds/worksheets/(.-)/private/full/(.-)<.-<title type=.text.>(.-)</title>.-</entry>") do
    spreadsheet.worksheets[title] = { id = id, rows = tonumber( rows ), columns = tonumber( columns ) }
    --table.insert( spreadsheet.worksheets, { id = id, title = title, rows = tonumber( rows ), columns = tonumber( columns ) } )
  end

  return spreadsheet
end


function GoogleSpreadsheet:append( row, worksheetid )
  local worksheetid = worksheetid or 1

  if self.key == nil then error( 'no spreadsheet specified' ) end

  local api = GoogleAPI:oauthlogin( GoogleSpreadsheet.refresh_token )

  --ngx.log( ngx.DEBUG, inspect( row ) )

  local entry = '<entry xmlns="http://www.w3.org/2005/Atom" xmlns:gsx="http://schemas.google.com/spreadsheets/2006/extended">'
    for name, value in pairs( row ) do
      local cleaned_name = name:gsub( ' ', '' ):gsub( '_', '' ):gsub( '/', '' ):lower()
      local cleaned_value = value:gsub( '&', 'and' )
      entry = entry..'<gsx:'..cleaned_name..'>'..cleaned_value..'</gsx:'..cleaned_name..'>';
    end
  entry = entry ..'</entry>'

  --ngx.log( ngx.DEBUG, inspect( entry ) )

  local options = {
    method = ngx.HTTP_POST,
    body = entry
  }

  -- remove urlencoding content type
  ngx.req.set_header( 'Content-Type', 'application/atom+xml' )

  local res = api:oauthrequest( '/feeds/list/'..self.key..'/'..worksheetid..'/private/full', options, GoogleSpreadsheet.api_proxy )

  return res

end


function GoogleSpreadsheet:rows( columns, worksheet_name, options )
  local columns = columns or {}
  local options = options or {}

  local worksheetid = ''
  if not worksheet_name then
    worksheet_name = next( self.worksheets )
  end
  worksheetid = self.worksheets[worksheet_name].id
      
  local api = GoogleAPI:oauthlogin( GoogleSpreadsheet.refresh_token )

  local api_options = {}
  local rows = {}
  
  local res = api:oauthrequest( '/feeds/list/'..self.key..'/'..worksheetid..'/private/full', api_options, GoogleSpreadsheet.api_proxy )

  for entry in res.body:gmatch( "<entry>(.-)</entry>" ) do

    local row = {}
    for _, column in ipairs( columns ) do
      local name = column:gsub( ' ', '' ):lower()

      local entry = entry:match( '<gsx:'..name..'>(.-)</gsx:'..name..'>' )

      if options.trim == true then
        entry = entry:trim()
      end

      row[column] = entry

    end
    table.insert( rows, row )

  end

  return rows

end


return GoogleSpreadsheet
