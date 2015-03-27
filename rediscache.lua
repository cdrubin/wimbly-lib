
local RedisCache = {}


local mt = {}
mt.__index = function( table, key )
  local red = ngx.ctx.redis[ table.host..table.port ]
  return red[key]
end


function RedisCache.connect( host, port )

  local object = {}
  object.host = host or '127.0.0.1'
  object.port = port or '6379'

  if not ngx.ctx.redis then
    ngx.ctx.redis = {}
  end

  if not ngx.ctx.redis[ object.host..object.port ] then
    
    local redis = require( 'resty.redis' )
    local red = redis:new()

    red:set_timeout( 1000 )
    
    local ok, err = red:connect( object.host, object.port )

    if not ok then
      ngx.say( "failed to connect: ", err )
      return
    end
  
    ngx.ctx.redis[ object.host..object.port ] = red
  end
  
  local mt = {}
 
  mt.__index = function( table, key )
    local red = ngx.ctx.redis[ table.host..table.port ]
    return red[key]
  end

  setmetatable( object, mt )
  return object

end




return RedisCache
