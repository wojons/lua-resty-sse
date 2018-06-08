local http = require "resty.http" -- https://github.com/pintsized/lua-resty-http

local _M = {_VERSION = '0.2.0'}
_M.__index = _M

-- variable caching (https://www.cryptobells.com/properly-scoping-lua-nginx-modules-ngx-ctx/)
local str_find   = string.find
local str_sub    = string.sub
local str_gfind  = string.gfind or string.gmatch -- http://lua-users.org/lists/lua-l/2013-04/msg00117.html
local tbl_insert = table.insert

local user_agent_header = "lua-resty-sse-v ".._M._VERSION

local function str_ltrim(s) -- remove leading whitespace from string.
  return (s:gsub("^%s*", ""))
end

local function str_split(str, delim)
    local result    = {}
    local pat       = "(.-)"..delim.."()"
    local lastPos   = 1

    for part, pos in str_gfind(str, pat) do
        tbl_insert(result, part)
        lastPos = pos
    end -- for
    tbl_insert(result, str_sub(str, lastPos))
    return result
end -- split

function _M.new()
    local httpc, err = http.new()
    if not httpc then return nil, err end
    local that = {httpc=httpc,buffer=''}
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
    return self.httpc:connect(...)
end -- connect

local function _headers_format_request(headers)
    if type(headers) ~= "table" then headers = {} end

    headers['Accept'] = "text/event-stream"

    if not headers['User-Agent'] then headers['User-Agent'] = user_agent_header end

    return headers
end -- headers_format_request

function _M.request(self, params)
    params = params or {}
    params.method  = "GET"
    params.headers = _headers_format_request(params.headers)

    local res, err = self.httpc:request(params)
    if err then return nil, err end

    self.res = res
    return res, err
end -- request

function _M.request_uri(self, uri, params)
    local parsed_uri, err = self.httpc:parse_uri(uri)
    if not parsed_uri then return nil, err end

    local _, host, port, path = unpack(parsed_uri)

    local c
    c, err = self:connect(host, port)
    if not c then return nil, err end

    params = params or {}
    params.path    = path
    params.headers = _headers_format_request(params.headers)
    if not params.headers['Host'] then params.headers['Host'] = host end

    return self:request(params)
end -- request_uri

-- It parses until a full frame of an SSE event if found and decoded
local function _parse_sse(buffer)
    local struct         = { event = nil, id = nil, data = {} }
    local struct_started = false
    local frame_break   = str_find(buffer, "\n\n") -- make sure we have at least one frame ini this
    local buffer_lines

    if frame_break ~= nil then
        buffer_lines = str_split(str_sub(buffer, 1, frame_break), "\n") -- get one frame from the buffer and split it into lines
    else
        return nil, buffer, nil
    end -- if

    for _, dat in pairs(buffer_lines) do
        local s1, _ = str_find(dat, ":") -- find where the cut point is

        if s1 and s1 ~= 1 then
            local field = str_sub(dat, 1, s1-1) -- returns "data " from data: hello world
            local value = str_ltrim(str_sub(dat, s1+1)) -- returns "hello world" from data: hello world

            if field then struct_started = true end

            -- for now not checking if the value is already been set
            if     field == "event" then struct.event = value
            elseif field == "id"    then struct.id = value
            elseif field == "data"  then tbl_insert(struct.data, value)
            end -- if
        end -- if
    end -- for

    -- reply back with the rest of the buffer
    buffer = str_sub(buffer, frame_break+2) -- +2 because we want to be on the other side of \n\n

    if struct_started then
        return struct, buffer
    end
    return nil, buffer
end -- parse_sse

function _M.headers_check_response(self)
    -- check to make sure the status code that came back is the coorect range
    if self.res.status < 200 or self.res.status > 299 then
        return nil, "Status Non-200 ("..self.res.status..")"
    end -- if

    -- make sure we got the right content type back in the headers
    local find_mime, _ = str_find(self.res.headers["Content-Type"], "text/event-stream",1,true)
    if find_mime == nil then
        return nil, "Content Type not text/event-stream ("..self.res.headers["Content-Type"]..")"
    end

    return true
end -- headers_check_response

-- It receives "lines" from the socket until one (or both) occurs:
--   error reading from the socket (including read timeouts)
--   an SSE event was found and decoded
function _M.receive(self)
    local chunk, err, pchunk, struct, parse_err
    local sock = self.httpc.sock
    local reader = sock.receive

    repeat
        chunk, err, pchunk = reader(sock,'*l')

        if chunk or pchunk then
            if chunk then self.buffer = self.buffer .. chunk .. '\n' end  -- we got a full line (without the ending \n)

            if pchunk then self.buffer = self.buffer .. pchunk end -- we did not get a full line, but a partial one

            struct, self.buffer, parse_err = _parse_sse(self.buffer) -- parse the data that is in the buffer

            if parse_err then return struct, parse_err end
        end
    until err or struct or not (chunk or pchunk)

    return struct, err
end

return _M
