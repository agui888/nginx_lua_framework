#!/usr/bin/env lua
-- -*- lua -*-

module('fuhao.redis_conn', package.seeall)

local Redis = require("resty.redis")

local redis_pool = {}

function redis_pool:get_redis_conf()
    local fuhaoutil = require("fuhao.util")
    local redis_config = fuhaoutil.get_config("redis")
    local redis_host = "127.0.0.1"
    local redis_port = 6379
    local redis_timeout = 10000
    local redis_poolsize= 2000
    if redis_config and type(redis_config.host) == "string" then
        redis_host = redis_config.host
    end
    
    if redis_config and type(redis_config.port) == "number" then
        redis_port = redis_config.port
    end

    if redis_config and type(redis_config.timeout) == "number" then
        redis_timeout= redis_config.timeout
    end
    
    if redis_config and type(redis_config.poolsize) == "number" then
        redis_poolsize= redis_config.poolsize
    end
    logger:i(redis_host..":"..tostring(redis_port).."  "..tostring(redis_timeout).."  "..tostring(redis_poolsize))
    return redis_host,redis_port,redis_timeout,redis_poolsize
end

function redis_pool:get_redis_conn()
    if ngx.ctx[redis_pool] then
         return ngx.ctx[redis_pool]
    end
    local red = Redis:new()
    local redis_host,redis_port,redis_timeout,redis_poolsize= redis_pool:get_redis_conf()
    local ok, err = red:connect(redis_host,redis_port)
    if not ok then
        logger:e({"failed to connect: ", err})
        return nil, err
    end
    logger:i("connect redis completed!")
    red:set_timeout(redis_timeout)

--[[
    local ok1, err1 = red:set_keepalive(redis_timeout, redis_poolsize)
    if not ok1 then
         ngx.log(ngx.ERR, err);
         ngx.say("failed to set keepalive: ", err1)
         return nil,err
    end
--]]
    ngx.ctx[redis_pool] = red 
    return ngx.ctx[redis_pool]
end

function redis_pool:close()
     if ngx.ctx[redis_pool] then
         local redis_host,redis_port,redis_timeout,redis_poolsize= redis_pool:get_redis_conf()
         ngx.ctx[redis_pool]:set_keepalive(redis_timeout, redis_poolsize)
         ngx.ctx[redis_pool] = nil
     end
 end

return redis_pool