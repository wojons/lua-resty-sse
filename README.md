# lua-resty-sse

Lua Server Side Events client cosocket driver for [OpenResty](http://openresty.org/) / [ngx_lua](https://github.com/openresty/lua-nginx-module).

# Status

This library is still under active development and is considered production ready.

## Synopsis

``` lua
lua_package_path "/path/to/lua-resty-sse/lib/?.lua;;";

server {

  location /simpleinterface {
    resolver 8.8.8.8;  # Google open DNS server for an example

    content_by_lua_block {

      local SSE = require "resty.sse"

      local headers = {
        ["X-Some-Header-Field"] = "foobar"
      }
      local sse = SSE.new("http://some-pub-sub-server.com/subscriber", headers) --header table is optional
      --never fails, always returns new sse 'object'

      --explicitly calling :connect() is optional. SSE will connect as needed
      local ok, err = sse:connect()
      if not ok then 
        ngx.say("SSE failed: ", err)
        return
      end

      --message processing loop 
      for evt in sse:events() do
        ngx.say("SSE id:", evt.id or "")
        ngx.say("SSE event-type:", evt.type)
        ngx.say("SSE data:", evt.data)
      end
      
      --why did we exit the message processing loop?
      if sse.error then
        ngx.say("SSE error:", sse.error)
      end
  }
}
```

# API

## SSE.new(url, headers)

```lua 
  local SSE = require "resty.sse"
  local sse_client = SSE.new("http://sse_server.example/sse_url")
```
return new `sse` object, ready to connect to `url` with optional `headers` table

## sse:connect()
```lua
  local res, err = sse_client:connect()
```
attempt to connect to SSE server. return `true` on success, `nil, error` on failure.

It is _not necessary_ to call this function explicitly, the `sse` client will attempt to `connect()` as needed.

## sse:close()

close the connection

## sse.error

last error string from running the `sse` client, or nil when running without errors

## sse:events()

`for`-loop iterator to receive SSE events:

```lua

for evt in sse:events() do
  --handle evt
end

--why did we exit the loop?
if sse.error then
  --handle error stuff
end
```
