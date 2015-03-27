
--local Model = require( 'models/base' )
local AmazonS3 = class( 'AmazonS3' )


-- client login uses an email and password to get access to old APIs
function AmazonS3.static.list( bucket )

  local res = ngx.location.capture( '/proxy/s3/'..bucket )

--[=[
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
  <Name>fax-readingandwritingproject-com</Name>
  <Prefix></Prefix>
  <Marker></Marker>
  <MaxKeys>1000</MaxKeys>
  <IsTruncated>false</IsTruncated>
  <Contents>
    <Key>131B65B1-6AD1-45B8-8691-48B10087413A_XXXX.pdf</Key>
    <LastModified>2014-02-04T16:25:27.000Z</LastModified>
    <ETag>&quot;c34d970400c3e7a43bb36c8c60186952&quot;</ETag>
    <Size>112063</Size>
    <Owner>
      <ID>6b67e1001df5a1c14d7a5baedfd3bab65d99a1bf17dca65f52557a9c6ad07cca</ID>
      <DisplayName>rwproject</DisplayName>
    </Owner>
    <StorageClass>STANDARD</StorageClass>
  </Contents>
  <Contents>
    <Key>5E422BD3-FFCB-47BB-9D1C-0F97B7A0AE9D_1657.pdf</Key>
    .
    .
    .
    <StorageClass>STANDARD</StorageClass>
  </Contents>
</ListBucketResult>
--]=]

  local list = {}
  local current = {}
  local tag = ''

  local sax = slaxml:parser{
    startElement = function( name, nsURI )
      if name == 'Key' then tag = 'key'
      elseif name == 'LastModified' then tag = 'created_on'
      else tag = '' end
    end,
    closeElement = function( name, nsURI )
      if name == 'LastModified' then table.insert( list, current ); current = {} end
    end,
    text = function(text)
      if tag ~= '' then current[tag] = text end
    end
  }

  sax:parse( res.body )
  
  return list

end


function AmazonS3.static.upload( from, to )
  
  local destination_bucket, destination_key = to:match( '^([^%/]+)/(.+)$' )
  
  local file = io.open( from )
  local content = file:read( '*all' )
  file:close()
  
  ngx.req.set_header( 'Host', destination_bucket..'.s3.amazonaws.com' )
  ngx.req.set_header( 'Date', ngx.cookie_time( ngx.time() ) )
  ngx.req.set_method( ngx.HTTP_PUT )
  local res = ngx.location.capture( '/proxy/s3/'..destination_bucket..'/'..destination_key:gsub( ' ', '+' ), { method = ngx.HTTP_PUT, body = content } )

  return ( res.status == 200 ), res.body
  
end


function AmazonS3.static.copy( from, to )

  local source_bucket, source_key = from:match( '^([^%/]+)/(.+)$' )
  local destination_bucket, destination_key = to:match( '^([^%/]+)/(.+)$' )

  ngx.log( ngx.DEBUG, source_bucket )
  ngx.log( ngx.DEBUG, source_key )
  ngx.log( ngx.DEBUG, destination_bucket )
  ngx.log( ngx.DEBUG, destination_key )
    
  --[[
  PUT /destinationObject HTTP/1.1
  Host: destinationBucket.s3.amazonaws.com
  x-amz-copy-source: /source_bucket/sourceObject
  x-amz-metadata-directive: metadata_directive
  x-amz-copy-source-if-match: etag
  x-amz-copy-source-if-none-match: etag
  x-amz-copy-source-if-unmodified-since: time_stamp
  x-amz-copy-source-if-modified-since: time_stamp
  <request metadata>
  Authorization: authorization string (see Authenticating Requests (AWS Signature Version 4))
  Date: date
  --]]
  
  ngx.req.set_header( 'Host', destination_bucket..'.s3.amazonaws.com' )  
  ngx.req.set_header( 'x-amz-copy-source', '/'..source_bucket..'/'..source_key )
  ngx.req.set_method( ngx.HTTP_PUT )
  
  local destination = ( destination_bucket..'/'..destination_key ):gsub( ' ', '+' )
  local res = ngx.location.capture( '/proxy/s3/'..destination, { method = ngx.HTTP_PUT } )

  ngx.req.clear_header( 'Host' )  
  ngx.req.clear_header( 'x-amz-copy-source' )

  
  return ( res.status == 200 ), res.body
end


function AmazonS3.static.delete( key )

  ngx.req.set_method( ngx.HTTP_DELETE )

  local res = ngx.location.capture( '/proxy/s3/'..key:gsub( ' ', '+' ), { method = ngx.HTTP_DELETE } )  
  
  return ( res.status == 204 ), res.body
end

return AmazonS3
