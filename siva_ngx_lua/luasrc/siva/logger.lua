#!/usr/bin/env lua
-- -*- lua -*-
-- Copyright 2015 siva Inc.
-- Author : fuhao 
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

module("siva.logger", package.seeall)

local string_sub = string.sub
local string_lower  = string.lower
local string_format = string.format
local debug_getinfo = debug.getinfo
local io_open       = io.open
local os_date       = os.date
local ngx_time      = ngx.time
local string_upper  = string.upper

logging = require("logging")
sivautil = require("siva.util")
sivavars = require("siva.vars")


function get_logger(appname)
    local logger = sivavars.get(appname, "__LOGGER")
    if logger then return logger end
    local getLogConf= function()
        local filename = "/dev/stderr"
        local level = "DEBUG"
        -- local log_config = sivautil.get_config(appname, "logger")
        local log_config = sivautil.get_config("logger")
    
        if log_config and type(log_config.file) == "string" then
            filename = log_config.file
        end
    
        if log_config and type(log_config.level) == "string" then
            local tmp = string_upper(log_config.level)
            if not logging.LEVELS[tmp] then
                tmp = 'DEBUG'
            end
            level = tmp
        end
        return filename,level
    end

    local log_filename = function(date)
      local fn,_ = getLogConf() 
      return fn .. '.' .. date
    end
    local f_date = os_date("%Y-%m-%d", ngx_time())
    local fname = log_filename(f_date)
    local f = io_open(fname, "a")
    if not f then
        f = io_open("/dev/stderr", "a")
        ngx.log(ngx.ERR, string_format("LOGGER ERROR: file `%s' could not be opened for writing", filename))
    end
    f:setvbuf("line")

    local function log_appender(self, level, message)
        local date  = os_date("%Y-%m-%d %H:%M:%S", ngx_time())
        local frame = debug_getinfo(4)
        local s = string_format('[%s] [%s] [%s:%d] %s\n',
                                string_sub(date, 6),
                                level,
                                frame.short_src,
                                frame.currentline,
                                message)
        local log_date = string_sub(date, 1, 10)
        local nowFName = log_filename(f_date)
        if fname ~= nowFName  then
          f_date = log_date
          f:close()
          f = io_open(log_filename(log_date), "a")
          f:setvbuf("line")
        end
        f:write(s)
        return true
    end
    
    local logger = logging.new(log_appender)
    local _,level = getLogConf()
    logger:setLevel(level)
    sivavars.set(appname, "__LOGGER", logger)
    logger._log = logger.log
    logger._setLevel = logger.setLevel

    logger.log = function(self, level, ...)
                     local _logger = get_logger(ngx.ctx.SIVA_NGX_LUA_APP_NAME)
                     _logger._log(self, level, ...)
                 end
    logger.setLevel = function(self, level, ...)
                          local _logger = get_logger(ngx.ctx.SIVA_NGX_LUA_APP_NAME)
                          _logger:_log("ERROR", "Can not setLevel")
                      end
    -- for _, l in ipairs(logging.LEVEL) do -- logging does not export this variable :(
    local levels = {d = "DEBUG", i = "INFO", w = "WARN", e = "ERROR", f = "FATAL"}
    for k, l in pairs(levels) do
        logger[k] = function(self, ...)
                        logger.log(self, l, ...)
                    end
        logger[string_lower(l)] = logger[k]
    end
    logger.tostring = logging.tostring
    logger.table_print = sivautil.table_print
    
    return logger
end

function logger()
    local logger = get_logger(ngx.ctx.SIVA_NGX_LUA_APP_NAME)
    return logger
end

