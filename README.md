# lua-resty-sse

Lua Server Side Events client cosocket driver for [OpenResty](http://openresty.org/) / [ngx_lua](https://github.com/openresty/lua-nginx-module).

# Status

This library is still under active development and is considered production ready.

# API

* [new](#name)
* [connect](#connect)
* [set_timeout](#set_timeout)
* [set_keepalive](#set_keepalive)
* [get_reused_times](#get_reused_times)
* [close](#close)
* [request](#request)
* [request_uri](#request_uri)
* [receive](#receive)

## Synopsis

```` lua
lua_package_path "/path/to/lua-resty-sse/lib/?.lua;;";

server {


  location /simpleinterface {
    resolver 8.8.8.8;  # Google's open DNS server for an example

    content_by_lua_block {
      local sse = require "resty.sse"

      local conn, err = sse.new()
      if not conn then
        ngx.say("failed to get connection: ", err)
      end

      local res, err = conn:request_uri("http://some-pub-sub-server.com/subscriber")

      if not res then
        ngx.say("failed to request: ", err)
        return
      end

      while true
        local event, err = conn:receive()
        if err then ngx.say("got an error: ", err) end
        if event then  ngx.say("got an event: ", event) end
      end
    }
  }
}
````

# Connection

## new

TODO

## connect

TODO

## set_timeout

TODO

## set_keepalive

TODO

## get_reused_times

TODO

## close

TODO

## request

TODO

## request_uri

TODO

## receive

TODO
