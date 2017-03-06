local http = require "resty.sse.http"
local cjson = require "cjson"

local _M = {_VERSION = '0.0.3'}
_M.__index = _M

function _M.new()
    local httpc, err = http.new()
    if not httpc then
        return nil, err
    end
    local that = {httpc=httpc}
    setmetatable(that, _M)
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
    params["method"]  = "GET"
    params["headers"] = self:headers_format_request(params["headers"])

    local res, err = self.httpc:request(params)
    if err then
        return nil, err
    end -- if

    self.res = res
    return res, err
end -- request

function _M.request_uri(self, uri, params)
    local parsed_uri, err = self.httpc:parse_uri(uri)
    if not parsed_uri then
        return nil, err
    end

    local scheme, host, port, path = unpack(parsed_uri)

    local c, err = self:connect(host, port)
    if not c then
        return nil, err
    end

    params["path"]    = path
    params["headers"] = self:headers_format_request(params["headers"])
    if params["headers"]["Host"] == nil then
        params["headers"]["Host"] = host
    end
    return self:request(params)
end -- request_uri

function _M.parse_sse(self, buffer)
    local strut         = { event = nil, id = nil, data = {} }
    local strut_started = false
    local buffer_lines  = nil
    local frame_break   = string.find(buffer, "\n\n") -- make sure we have at least one frame ini this
    local err           = nil

    if frame_break ~= nil then
        buffer_lines = self.split(string.sub(buffer, 1, frame_break), "\n") -- get one frame from the buffer and split it into lines
    else
        return nil, buffer, nil
    end -- if

    for _, dat in pairs(buffer_lines) do
        local s1, s2 = string.find(dat, ":") -- find where the cut point is

        if s1 and s1 ~= 1 then
            local field = string.sub(dat, 1, s1-1) -- returns "data " from data: hello world
            local value = self:ltrim(string.sub(dat, s1+1)) -- returns "hello world" from data: hello world
            -- note: make sure to trim leading whitespace

            if field then strut_started = true end

            -- for now not checking if the value is already been set
            if     field == "event" then strut.event = value
            elseif field == "id"    then strut.id = value
            elseif field == "data"  then table.insert(strut.data, value)
            end -- if
        else
            -- this is for comments
        end -- if
    end -- for

    -- reply back with the rest of the buffer
    buffer = string.sub(buffer, frame_break+2) -- +2 because we want to be on the other side of \n\n

    if strut_started then
        return strut, buffer, err
    else
        return nil, buffer, err
    end
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
    local find_mime = nil

    -- check to make sure the status code that came back is the coorect range
    if self.res.status < 200 and self.res.status > 299 then
        return nil, "Status Non-200 ("..self.res.status..")"
    end -- if

    -- make sure we got the right content type back in the headers
    find_mime, _ = string.find(self.res.headers["Content-Type"], "text/event-stream")
    if find_mime == nil then
        return nil, "Content Type not text/event-stream"
    end

    return true

end -- headers_check_response

function _M.split(str, delim)
    local result    = {}
    local pat       = "(.-)"..delim.."()"
    local lastPos   = 1

    local gfind = string.gfind or string.gmatch -- http://lua-users.org/lists/lua-l/2013-04/msg00117.html
    for part, pos in gfind(str, pat) do
        table.insert(result, part)
        lastPos = pos
    end -- for
    table.insert(result, string.sub(str, lastPos))
    return result
end -- split

local default_callbacks = {
    error = function(chunk, err)
        ngx.log(ngx.ERR, cjson.encode({chunk = chunk, error = err}))
        ngx.flush(false)
    end, -- function
    event = function(strut)
        ngx.say(cjson.encode({strut = strut}))
        ngx.flush(true)
    end -- function
}

function _M.sse_loop(self, max_buffer, event_cb, error_cb)

    local reader = nil
    local parse_err = nil
    local strut     = nil

    --only run this if we have run this before
    if self.read_before then
        reader = self.httpc:w_body_reader(self.httpc.sock, nil, 65536)
        --reader = self.httpc:w_body_reader(self.httpc.sock, nil, nil)
    else
        self.read_before = true -- set that we have read something off this buffer at least once
        self.buffer = ""  -- initialize buffer
        reader = self.res.body_reader -- get the parent reader
    end -- if

    if not event_cb then event_cb = default_callbacks.event end
    if not error_cb then error_cb = default_callbacks.error end

    repeat
        local chunk, err, pchunk= reader("*l")
        if err then -- if we have an error show it and and then hop out
            chunks = cjson.encode({chunk, pchunk})
            error_cb(chunks, err)
            break -- break out of the code
        end -- if

        if chunk ~= nil then -- this means we got a full line from the system
            self.buffer = self.buffer .. chunk .. "\n" -- update the buffer with the new chunk
        end -- if

        if pchunk ~= nil then -- this means we did not get a full line
            self.buffer = self.buffer .. pchunk
        end -- if

        -- todo: we may want to run this on pchunk but not sure yet
        while chunk ~= nil or self.buffer:len() > 0 do
        -- until strut == nil or self.buffer:len() == 0 or parse_err ~= nil or leave == true

            -- parse the data that is in the buffer
            strut, self.buffer, parse_err = self:parse_sse(self.buffer)
            if strut ~= nil and strut ~= false then
                local leave = event_cb(strut)
            end -- if

            -- lets see if its time to blow this popsical joint
            if strut == nil or strut == false or leave == true or parse_err ~= nil then
                if parse_err ~= nil then
                    -- speak about the parse error
                end -- if

                break
            end -- if
        end -- while

    until not chunk or not pchunk -- because we have nothing to do
end -- sse_loop

-- remove trailing and leading whitespace from string.
function _M.trim(self, s)
  -- from PiL2 20.4
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- remove leading whitespace from string.
function _M.ltrim(self, s)
  return (s:gsub("^%s*", ""))
end

-- remove trailing whitespace from string.
function _M.rtrim(self, s)
  local n = #s
  while n > 0 and s:find("^%s", n) do n = n - 1 end
  return s:sub(1, n)
end

return _M
