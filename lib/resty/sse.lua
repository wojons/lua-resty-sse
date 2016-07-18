local http = require "resty.http"

local _M = {_VERSION = '0.0.1'}

function _M.new(self)
    self.httpc = http.new()
end

function _M.set_timeout(self, timeout)
    return self.httpc:set_timeout(timeout)
end

function _M.set_keepalive(self, ...)
    return self.httpc:set_keepalive(...)
end

function _M.get_reused_times(self, ...)
    return self.httpc:get_reused_times(...)
end

function _M.close(self)
    self.httpc:close()
end

function _M.connect(self, ...)
    return self.httpc:connect(...)
end

function _M.request(self, params)
    local res, err = self.httpc:request(params)
    if err then
        return nil, err
    end

    self.res = res
    return res, err
end

function _M.parse_sse(self, buffer)
    local strut = { event = nil, id = nil, data = {} }

    local buffer_lines = self.split(buffer, "\r\n")
    local size = table.getn(buffer_lines)
    if buffer_lines[size] ~= "" and buffer_lines[size-1] ~= "" then
        return nil, buffer, "Not enough data"
    end

    for dex, dat in pairs(buffer_lines) then
        local s1, s2 = string.find(dat, ":")
        if s1 == nil then

        end
        local field = string.sub(dat, 1, s1-1)
        local value = string.sub(dat, s1+1)
        -- note: make sure to trim leading whitespace

        if field == "event" then
            if strut.event == nil then
                strut.event = value
            else
            end
        elseif field == "id" then
            if strut.id == nil then
                strut.id = value
            else
            end
        elseif field == "data" then
            table.insert(strut.data, value)
        end


    end



    -- return the data strut and a new buffer that missing the data we parsed and an er ror if it happenes
    return strut, buffer, err
end

function _M.split(str, delim)
    local result,pat,lastPos = {},"(.-)" .. delim .. "()",1
    for part, pos in string.gfind(str, pat) do
        table.insert(result, part); lastPos = pos
    end
    table.insert(result, string.sub(str, lastPos))
    return result
end

function _M.request_uri(self, uri, params)

    local res, err = self.httpc:request_uri(uri, params)
    if err then
        return nil, err
    end

    self.res = res
    return res, err
    --res.body = nil -- remove the body since we wont need it
end


function _M.sse_loop(self, max_buffer, event_cb, error_cb)

    local reader = self.res.body_reader
    local strut = nil
    local buffer = ""
    local parse_err = nil

    if max_buffer == nil then
        max_buffer = 65536
    end

    repeat
        local chunk, err = reader(max_buffer)
        if err then
            error_cb(chunk, err)
            break
        end

        if chunk then

            buffer = buffer + chunk
            strut = nil
            parse_err = nil

            repeat
                strut, buffer, parse_err = self.parse_sse(buffer)
                event_cb(strut)
            until buffer == 0 or parse_err ~= nil

        end
    until not chunk
end
