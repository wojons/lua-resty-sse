local http = require "resty.http" -- https://github.com/pintsized/lua-resty-http

local unpack = table.unpack or unpack

local SSE_metatable
local SSE_module = {
  _VERSION = '0.2.0',
  new = function(url, headers)
    return setmetatable({
      request_url = url,
      request_headers = headers or {}
    }, SSE_metatable)
  end
}

local SSE = {}
SSE_metatable = {__index = SSE}

SSE.connect_timeout = 5000 --default connect timeout is 5 minutes
SSE.readline_timeout = 1000*60*60*24*10 -- 10 days in msec

function SSE:connect()
  if self.http_client then
    return nil, "already connected"
  end
  
  local httpc, err = http.new()
  if not httpc then
    self.error = err
    return nil, err
  end
  
  httpc:set_timeouts(self.connect_timeout, self.readline_timeout, self.readline_timeout)

  local parsed_uri, err = httpc:parse_uri(self.request_url)
  if not parsed_uri then
    self.error = err
    return nil, err
  end

  local _, host, port, path = unpack(parsed_uri)

  local ok, err = httpc:connect(host, port)
  if not ok then
    self.error = err
    return nil, err
  end

  local headers = self.request_headers
  headers['Accept'] = "text/event-stream"
  headers['Host'] = host
  if headers['User-Agent'] == nil then
    headers['User-Agent'] = "lua-resty-sse/" .. SSE_module._VERSION
  end

  local response, err = httpc:request({
    method = "GET",
    path = path,
    headers = headers,
  })

  if not response then
    self.error = err
    return nil, err
  end

  -- check to make sure the status code that came back is the correct range
  if response.status < 200 or response.status > 299 then
    self.error = "bad response status code: " .. response.status
    return nil, self.error
  end
  -- make sure we got the right content type back in the headers
  local content_type = response.headers["Content-Type"]
  if not content_type then
    self.error = "Content-Type missing in response"
    return nil, self.error
  elseif not content_type:match("text/event%-stream") then
    self.error = "Content Type not text/event-stream ("..content_type..")"
    return nil, self.error
  end

  self.error = nil
  self.http_client = httpc
  --set a _really_ long timeout
  
  return true
end

function SSE:close()
  self.http_client:close()
  self.http_client = nil
end

-- for event in sse:events do
--   ...
--end
function SSE:events()
  if not self.http_client then
    self:connect()
  end

  if not self.http_client or self.error then
    --we have no connection
    return function() end
  end

  local evt_type, evt_id, evt_data = nil ,nil, {}

  local line, err, partial
  local socket = self.http_client.sock
  local function readline()
    line, err, partial = socket:receive("*l")
    if not line then
      if err == "timeout" then --we don't care about timeouts
        --ngx.log(ngx.ERR, "ignore timeout")
        return readline() --no stack overflow danger, tail recusion calls are optimized away
      else
        self.error = err
      end
    end
    -- pretty sure we don't care about partial reads. whole lines only plz
    return line
  end

  self.error = nil

  --iterator for for-loop
  return function()
    while readline() do
      if #line > 0 then
        local lbl, val = line:match("(%w*): (.*)")
        if lbl     == "data" then
          table.insert(evt_data, val)
        elseif lbl == "id" then
          evt_id = val
        elseif lbl == "event" then
          evt_type = val
        end
        --otherwise it's an invalid line or a comment. we can ignore those
      else
        --event end
        if #evt_data > 0 then
          --build event data
          local event = {
            data = table.concat(evt_data, "\n"),
            id = evt_id,
            event = evt_type or "message"
          }
          --reset buffers
          evt_data, evt_id, evt_type = {}, nil, nil
          return event
        else
          -- extra newline? whatever, ignore it, even though that's kinda invalid
        end
      end
    end
  end
end

return SSE_module
