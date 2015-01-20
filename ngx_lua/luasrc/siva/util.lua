#!/usr/bin/env lua
-- -*- lua -*-
-- Copyright 2012 Appwill Inc.
-- Author : KDr2
--
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
--

local json          = require("cjson")

local math_floor    = math.floor
local string_char   = string.char
local string_byte   = string.byte
local string_rep    = string.rep
local string_sub    = string.sub
local debug_getinfo = debug.getinfo

local fuhaovars = require("fuhao.vars")

module('fuhao.util', package.seeall)

function read_all(filename)
    local file = io.open(filename, "r")
    local data = ((file and file:read("*a")) or nil)
    if file then
        file:close()
    end
    return data
end


function setup_app_env(fuhao_home, app_name, app_path, global)
    global['FUHAO_NGX_LUA_HOME']=fuhao_home
    global['FUHAO_NGX_LUA_APP']=app_name
    global['FUHAO_NGX_LUA_APP_PATH']=app_path
    package.path = fuhao_home .. '/lualibs/?.lua;' .. package.path
    package.path = app_path .. '/app/?.lua;' .. package.path
    local request=require("fuhao.request")
    local response=require("fuhao.response")
    global['FUHAO_NGX_LUA_MODULES']={}
    global['FUHAO_NGX_LUA_MODULES']['request']=request
    global['FUHAO_NGX_LUA_MODULES']['response']=response
end


function loadvars(file)
    local env = setmetatable({}, {__index=_G})
    assert(pcall(setfenv(assert(loadfile(file)), env)))
    setmetatable(env, nil)
    return env
end

function get_config(key, default)
    if key == nil then return nil end
    local issub, subname = is_subapp(3)
    
    if not issub then -- main app
        local ret = ngx.var[key]
        if ret then return ret end
        local app_conf=fuhaovars.get(ngx.ctx.FUHAO_NGX_LUA_APP_NAME,"APP_CONFIG")

        local v = app_conf[key]
        if v==nil then v = default end
        return v
    end

    -- sub app
    if not subname then return default end
    local subapps=fuhaovars.get(ngx.ctx.FUHAO_NGX_LUA_APP_NAME,"APP_CONFIG").subapps or {}
    local subconfig=subapps[subname].config or {}

    local v = subconfig[key]
    if v==nil then v = default end
    return v
end

function _strify(o, tab, act, logged)
    local v = tostring(o)
    if logged[o] then return v end
    if string_sub(v,0,6) == "table:" then
        logged[o] = true
        act = "\n" .. string_rep("|    ",tab) .. "{ [".. tostring(o) .. ", "
        act = act .. table_real_length(o) .." item(s)]"
        for k, v in pairs(o) do
            act = act .."\n" .. string_rep("|    ", tab)
            act = act .. "|   *".. k .. "\t=>\t" .. _strify(v, tab+1, act, logged)
        end
        act = act .. "\n" .. string_rep("|    ",tab) .. "}"
        return act
    else
        return v
    end
end

function strify(o) return _strify(o, 1, "", {}) end

function table_print(t)
    local s1="\n* Table String:"
    local s2="\n* End Table"
    return s1 .. strify(t) .. s2
end

function table_real_length(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

function is_subapp(__call_frame_level)
    if not __call_frame_level then __call_frame_level = 2 end
    local caller = debug_getinfo(__call_frame_level,'S').source
    local main_app = ngx.var.FUHAO_NGX_LUA_APP_PATH
    
    local is_mainapp = (main_app == (string_sub(caller, 2, #main_app+1)))
    if is_mainapp then return false, nil end -- main app
    
    local subapps = fuhaovars.get(ngx.ctx.FUHAO_NGX_LUA_APP_NAME, "APP_CONFIG").subapps or {}
    for k, v in pairs(subapps) do
        local spath = v.path
        local is_this_subapp = (spath == (string_sub(caller, 2, #spath+1)))
        if is_this_subapp then return true, k end -- sub app
    end
    
    return false, nil -- not main/sub app, maybe call in fuhao_ngx_lua!
end

function parseNetInt(bytes)
    local a, b, c, d = string_byte(bytes, 1, 4)
    return a * 256 ^ 3 + b * 256 ^ 2 + c * 256 + d
end

function toNetInt(n)
    -- NOTE: for little endian machine only!!!
    local d = n % 256
    n = math_floor(n / 256)
    local c = n % 256
    n = math_floor(n / 256)
    local b = n % 256
    n = math_floor(n / 256)
    local a = n
    return string_char(a) .. string_char(b) .. string_char(c) .. string_char(d)
end

function write_jsonresponse(sock, s)
    if type(s) == 'table' then
        s = json.encode(s)
    end
    local l = toNetInt(#s)
    sock:send(l .. s)
end

function read_jsonresponse(sock)
    local r, err = sock:receive(4)
    if not r then
        logger:warn('Error when receiving from socket: %s', err)
        return
    end
    local len = parseNetInt(r)
    local data, err = sock:receive(len)
    if not data then
        logger:error('Error when receiving from socket: %s', err)
        return
    end
    return json.decode(data)
end

-- lua 字符串分割函数
-------------------------------------------------------
-- 参数:待分割的字符串,分割字符
-- 返回:子串表.(含有空串)
function lua_string_split(str, split_char)    
    local sub_str_tab = {};
    while (true) do        
        local pos = string.find(str, split_char);  
        if (not pos) then            
            local size_t = table.getn(sub_str_tab)
            table.insert(sub_str_tab,size_t+1,str);
            break;  
        end
 
        local sub_str = string.sub(str, 1, pos - 1);              
        local size_t = table.getn(sub_str_tab)
        table.insert(sub_str_tab,size_t+1,sub_str);
        local t = string.len(str);
        str = string.sub(str, pos + 1, t);   
    end    
    return sub_str_tab;
end



--[[
-------------------------------------------------------
-- 参数:待分割的字符串,分割字符
-- 返回:子串表.(含有空串)
function lua_string_split(str, split_char)
    local sub_str_tab = {};
    while (true) do
        local pos = string.find(str, split_char);
        if (not pos) then
            sub_str_tab[#sub_str_tab + 1] = str;
            break;
        end
        local sub_str = string.sub(str, 1, pos - 1);
        sub_str_tab[#sub_str_tab + 1] = sub_str;
        str = string.sub(str, pos + 1, #str);
    end

    return sub_str_tab;
end
--]]

function redis_hash_to_table(hash_data)
    local new_reply = { }
    for i = 1, #hash_data, 2 do new_reply[hash_data[i]] = hash_data[i + 1] end
    return new_reply
end
