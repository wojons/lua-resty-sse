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
* [sse_loop](#sse_loop)

## Synopsis

```` lua
lua_package_path "/path/to/lua-resty-sse/lib/?.lua;;";

server {


  location /simpleinterface {
    resolver 8.8.8.8;  # Google's open DNS server for an example

    content_by_lua '

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
        conn:sse_loop(nil, function(event)
          ngx.say("got an event: ", err)
        end, function(err)
          ngx.say("got an error: ", err)
        end)
      end
    ';
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

## sse_loop

TODO