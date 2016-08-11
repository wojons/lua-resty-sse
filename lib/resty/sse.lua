local http = require "resty.http"
local cjson = require "cjson"

local _M = {_VERSION = '0.0.1'}
_M.__index = _M

function _M.new()
    local that = {}
    setmetatable(that, _M)
    that.httpc = http.new()
    return that
end -- new

function _M.set_timeout(self, timeout)
    return self.httpc:set_timeout(timeout)
end -- set_timeout

function _M.set_keepalive(self, ...)
    return self.httpc:set_keepalive(...)
end -- set_keepalive

function _M.get_reused_times(self, ...)
    return self.httpc:get_reused_times(...)
end -- get_reused_times

function _M.close(self)
    self.httpc:close()
end -- close

function _M.connect(self, ...)
    self.read_before = false
    return self.httpc:connect(...)
end -- connect

function _M.request(self, params)
    params["headers"] = self:headers_format_request(params["headers"])

    local res, err = self.httpc:request(params)
    if err then
        return nil, err
    end -- if

    self.res = res
    return res, err
end -- request

function _M.request_uri(self, uri, params)
    ngx.log(ngx.DEBUG, uri)
    params["headers"] = self:headers_format_request(params["headers"])
    params["method"] = "GET"
    ngx.log(ngx.DEBUG, cjson.encode(params))
    local parsed_uri, err = self.httpc:parse_uri(uri)
    local scheme, host, port, path = unpack(parsed_uri)
    local c, err = self.httpc:connect(host, port)
    if not c then
        return nil, err
    end
    params["path"] = path
    params["headers"]["Host"] = host



    local res, err = self.httpc:request(params)
    --local res, err = self.httpc:request_uri(uri, params)
    if err then
        return nil, err
    end -- if

    self.res = res
    return res, err
    --res.body = nil -- remove the body since we wont need it
end -- request_uri

function _M.parse_sse(self, buffer)
    local strut = { event = nil, id = nil, data = {} }
    local strut_started = false
    local frame_buffer = self.split(buffer, "\n\n") -- group lines by frame
    local _, full_frame_count = buffer:gsub("\n\n", "\n\n") -- number of full frames that we have
    local frame_count = table.getn(frame_buffer) -- the number of frames we think we have
    local passes = 0 -- count the number of times we have gone around the loop
    local buffer_lines = nil

    ngx.log(ngx.INFO, cjson.encode(frame_buffer))
    --local empty_in_row = 0

    if full_frame_count > 0 then -- make sure we have enough to make up a frame
        ngx.log(ngx.DEBUG, frame_buffer[1])
        buffer_lines = self.split(frame_buffer[1], "\n")
        ngx.log(ngx.DEBUG, cjson.encode(buffer_lines))
    else
        return nil, buffer, nil
    end -- if

    local size = table.getn(buffer_lines)

    for dex, dat in pairs(buffer_lines) do
        --if dat == "" then
        --    -- update the buffer before we run away
        --    buffer = table.concat(buffer_lines, "\n", dex+1) -- whats left in the buffer after this line since this is empty
        --    break
        --else
        --    empty_in_row = 0
        --end -- if

        local is_comment = false

        local s1, s2 = string.find(dat, ":")
        if s1 == nil then
        elseif s1 == 1 then
            is_comment = true

        end -- if

        ngx.log(ngx.ERR, dat)

        if is_comment == false then
            strut_started = true
            local field = string.sub(dat, 1, s1-1)
            local value = string.sub(dat, s1+1)
            -- note: make sure to trim leading whitespace

            -- for now not checking if the value is already been set
            if field == "event" then
                strut.event = value
            elseif field == "id" then
                strut.id = value
            elseif field == "data" then
                table.insert(strut.data, value)
            end -- if
        end -- if

        passes = passes + 1
    end -- for


    --if passes == size then
    --    buffer = ""
    --end -- if
--[[ngx.log(ngx.ERR, passes)
    ngx.log(ngx.ERR, size)
    ngx.log(ngx.ERR, buffer)
    ngx.log(ngx.ERR, frame_buffer[1])
    ngx.log(ngx.ERR, frame_count)
    ngx.log(ngx.ERR, full_frame_count)
    ngx.log(ngx.ERR, buffer:len())]]--
    buffer = table.concat(frame_buffer, "\n\n", 2)
    --ngx.log(ngx.ERR, buffer)
    -- return the data strut and a new buffer that missing the data we parsed and an er ror if it happenes
    if strut_started == false then
        if passes > 0 then
            strut = false
        else
            strut = nil
        end -- if
    end
    return strut, buffer, err
end -- parse_sse

function _M.headers_format_request(self, headers)
    if type(headers) ~= "table" then
        headers = {}
    end -- if

    headers['Accept'] = "text/event-stream"

    if headers['User-Agent'] == nil then
        headers['User-Agent'] = "lua-resty-sse-v"
    end -- if

    return headers
end -- headers_format_request

function _M.headers_check_response(self)
    local mime = nil
    local content_type = self.split(self.res.headers["Content-Type"], ";")

    if self.res.status < 200 and self.res.status > 299 then
        return nil, "Status Non-200 ("..self.res.status..")"
    end -- if

    if table.get(content_type) > 0 then
        for dex, dat in pairs() do
            if string.find(dat, "/") ~= nil then
                mime = dat
            end -- if
        end -- for
    end -- if

    if mime ~= "text/event-stream" then
        return nil, "Contnt type not text/event-stream"
    end -- if

end -- headers_check_response

function _M.split(str, delim)
    local result,pat,lastPos = {},"(.-)" .. delim .. "()",1
    for part, pos in string.gfind(str, pat) do
        table.insert(result, part); lastPos = pos
    end -- for

    table.insert(result, string.sub(str, lastPos))
    return result
end -- split

function _M.sse_loop(self, max_buffer, event_cb, error_cb)

    local reader = self.res.body_reader

    --only run this if we have run this before
    if self.read_before == true then

        --reader = self.httpc:w_body_reader(self.httpc.sock, nil, 65536)
        reader = self.httpc:w_body_reader(self.httpc.sock, nil, nil)
    end -- if

    self.buffer = ""
    self.read_before = true -- set that we have read something off this buffer at least once
    local strut = nil
    local parse_err = nil

    -- if event_cb is not defined we will give a base one
    if event_cb == nil then
        event_cb = function(strut)
            ngx.say(cjson.encode({strut = strut}))
            ngx.flush(true)
        end -- function
    end -- if

    -- if the error_cb was not devined we will provide a base one
    if error_cb == nil then
        error_cb = function(chunk, err)
            ngx.log(ngx.ERR, cjson.encode({chunk = chunk, error = err}))
            ngx.flush(false)
        end -- function
    end -- if

    -- set_timeout the max buffer if one was not already defined
    if max_buffer == nil then max_buffer = 65536 end -- if

    repeat
        ngx.log(ngx.INFO, "top of loop")
        --local chunk, err, pchunk= reader(max_buffer)
        local chunk, err, pchunk= reader("*l")
        if err then -- if we have an error show it and and then hop out
            if type(error_cb) == "function" then error_cb(chunk, err) end -- if
            break -- break out of the code
        end -- if

        if chunk then
            --ngx.say(chunk)
            ngx.log(ngx.INFO, "sse-chunk -- ", chunk)
            if chunk ~= nil then
                self.buffer = self.buffer .. chunk -- update the buffer with the new chunk
            end

            if pchunk ~= nil then
                self.buffer = self.buffer .. pchunk
            end

            strut = nil
            parse_err = nil

            repeat
                -- parse the data that is in the buffer
                strut, self.buffer, parse_err = self:parse_sse(self.buffer)
                if strut ~= nil and strut ~= false then
                    local leave = event_cb(strut)
                end
            until strut == nil or self.buffer:len() == 0 or parse_err ~= nil or leave == true

        end -- if
    until not chunk -- because we have nothing to do
end -- sse_loop


return _M
