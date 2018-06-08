
package.path = './lib/?.lua;' .. package.path

local rex = require('rex_pcre') -- http://rrthomas.github.io/lrexlib/ PCRE flavor

local NgxSocketTcpMock = {}

function NgxSocketTcpMock.new()
	local mock = { sent = {} }
	setmetatable(mock,{__index=NgxSocketTcpMock})
	return mock
end

function NgxSocketTcpMock.connect(mock,host,port)
	mock.host = host
	mock.port = port
	return mock
end

function NgxSocketTcpMock.send(mock,stream)
	table.insert(mock.sent,stream)
	return #stream
end

function NgxSocketTcpMock.receive(mock,pattern)
  local stream = mock._stream_iterator and mock._stream_iterator()
  if stream then
		if type(stream) ~= "table" then return stream end
		return stream[1], stream[2], stream[3]
  end
  return nil, "EOF", nil -- no iterator or iterator finished, return end of file as if socket was closed
end

function NgxSocketTcpMock.deliver(mock,...)
  local idx = 1
  local arg_streams = {...}
  mock._stream_iterator = function()
    local elem = nil
    if idx <= #arg_streams then
      elem = arg_streams[idx]
      idx = idx + 1
    end
    return elem
  end
end

_G.unpack = table.unpack

_G.ngx = {
	socket = {
		tcp = (function()
			local next_socket = nil
			local tcp_mock = {
				next = function()
					next_socket = NgxSocketTcpMock.new()
					return next_socket
				end,
				retrieve = function()
					if next_socket then
						local socket = next_socket
						next_socket = nil
						return socket
					end
					return NgxSocketTcpMock.new()
				end
			}
			setmetatable(tcp_mock,{__call=tcp_mock.retrieve})
			return tcp_mock
		end)()
	},
	req = {

	},
	re = {
    match = function(subject,regex)
      local matches = table.pack(rex.match(subject,regex))
      if #matches < 1 then return nil end
      return matches
    end,
    find = function(subject,regex)
      return rex.find(subject,regex)
    end,
	},
	log = function(...)
		-- print(...)
	end,
	DEBUG = 'DEBUG',
	ERR = 'ERR',
	config = {
		ngx_lua_version = 'mock'
	}
}
