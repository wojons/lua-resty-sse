local http = require "resty.http"

local _M = {_VERSION = '0.0.1'}

function _M.new(self)
    self.httpc = http.new()
    return self
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
    params["headers"] = self:headers_format_request(params["headers"])

    local res, err = self.httpc:request_uri(uri, params)
    if err then
        return nil, err
    end -- if

    self.res = res
    return res, err
    --res.body = nil -- remove the body since we wont need it
end -- request_uri

function _M.parse_sse(self, buffer)
    local strut = { event = nil, id = nil, data = {} }

    local buffer_lines = self.split(buffer, "\r\n")
    local size = table.getn(buffer_lines)
    --local empty_in_row = 0
    local strut_started = false

    if size == 0 then
        return nil, buffer, nil
    end -- if

    for dex, dat in pairs(buffer_lines) then

        if dat == "" then
            -- update the buffer before we run away
            buffer = table.concat(buffer_lines, "\r\n", dex+1) -- whats left in the buffer after this line since this is empty
            break
        else
            empty_in_row = 0
        end -- if

        local s1, s2 = string.find(dat, ":")
        if s1 == nil then

        end -- if

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
    end -- for

    -- return the data strut and a new buffer that missing the data we parsed and an er ror if it happenes
    return strut, buffer, err
end -- parse_sse

function _M.headers_format_request(self, headers)
    if type(headers) ~= "table" then
        headers = {}
    end -- if

    headers['Accept'] = "text/event-stream"

    if headers['User-Agent'] == nil then
        headers['User-Agent'] = "lua-resty-sse-v".._M.VERSION
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
        for dex, dat in pairs() then
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
    local strut = nil
    local buffer = ""
    local parse_err = nil

    if max_buffer == nil then
        max_buffer = 65536
    end -- if

    repeat
        -- max size of that we will return as  note it may not be a whole "frame"
        local chunk, err = reader(max_buffer)
        if err then
            if type(error_cb) == "function" then
                error_cb(chunk, err)
            end -- if
            break
        end -- if

        if chunk then

            buffer = buffer + chunk
            strut = nil
            parse_err = nil

            repeat
                -- parse the data that is in the buffer
                strut, buffer, parse_err = self.parse_sse(buffer)
                local leave = event_cb(strut)
            until buffer == 0 or parse_err ~= nil or leave == true

        end -- if
    until not chunk
end -- sse_loop


return _M
