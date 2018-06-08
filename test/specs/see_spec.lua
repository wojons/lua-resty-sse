require('test.spec-helper')
local sse = require('resty.sse')

describe('sse', function()
	it("sends request",function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      ''
    )

		local sse_conn, res, err

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		assert.are.equal(res.status,200)
		assert.are.equal(res.reason,'OK')
		assert.are.same(res.headers,{['Content-Type'] = 'text/event-stream; charset=utf-8'})
		assert(sse_conn:headers_check_response(res))

		assert.matches('^GET /some/path HTTP/1.1\r\n',socket.sent[1])
		assert.matches('Host: some-server.com\r\n',socket.sent[1], nil, true)
		assert.matches('Accept: text/event-stream\r\n',socket.sent[1], nil, true)
		assert.matches('User-Agent: lua-resty-sse-v 0.2.0\r\n',socket.sent[1], nil, true)
	end)

	it("sends request with params",function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      ''
    )

		local sse_conn, res, err

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path',{
			headers = { foo = 'bar' },
			body    = 'something',
		})

		assert.is_nil(err)
		assert(sse_conn:headers_check_response(res))

		assert.matches('^GET /some/path HTTP/1.1\r\n',socket.sent[1])
		assert.matches('Host: some-server.com\r\n',socket.sent[1], nil, true)
		assert.matches('Accept: text/event-stream\r\n',socket.sent[1], nil, true)
		assert.matches('User-Agent: lua-resty-sse-v 0.2.0\r\n',socket.sent[1], nil, true)
		assert.matches('foo: bar\r\n',socket.sent[1], nil, true)
		assert.matches('Content-Length: 9\r\n',socket.sent[1], nil, true)
		assert.are.equal(socket.sent[2],'something')
	end)

	it('checks the response headers for OK responses',function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 404',
      'Content-Type: text/event-stream; charset=utf-8',
      ''
    )

		local sse_conn, res, err, ok

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		ok, err = sse_conn:headers_check_response(res)
		assert.is_falsy(ok)
		assert.are.equal(err,'Status Non-200 (404)')
	end)

	it('checks the response headers for correct content type',function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: application/json',
      ''
    )

		local sse_conn, res, err, ok

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		ok, err = sse_conn:headers_check_response(res)
		assert.is_falsy(ok)
		assert.are.equal(err,'Content Type not text/event-stream (application/json)')
	end)

	it("parses incoming events",function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      '',
      'event: foo',
      'id: 1476389203:0',
      'data: foo',
      '',
      'event: bar',
      'id: 1476389204:0',
      'data: bar',
      'data: quz',
      ''
    )

		local sse_conn, event, res, err

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		assert(sse_conn:headers_check_response(res))

		event, err = sse_conn:receive()
		assert.is_nil(err)
		assert.are.same(event,{ event = 'foo', id = '1476389203:0', data = {'foo'} })

		event, err = sse_conn:receive()
		assert.is_nil(err)
		assert.are.same(event,{ event = 'bar', id = '1476389204:0', data = {'bar','quz'} })

		event, err = sse_conn:receive()
		assert.are.equal(err,'EOF')
		assert.is_nil(event)
	end)

	it("stops receiving on a timeout",function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      '',
      'event: foo',
      {nil,'timeout',nil},
      'id: 1476389203:0',
      'data: foo',
      '',
      'event: bar',
      {nil,'timeout','id: 1476'},
      '389204:0',
      'data: bar',
      ''
    )

		local sse_conn, event, res, err

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		assert(sse_conn:headers_check_response(res))

		event, err = sse_conn:receive()
		assert.are.equal(err,'timeout')
		assert.is_nil(event)

		event, err = sse_conn:receive()
		assert.is_nil(err)
		assert.are.same(event,{ event = 'foo', id = '1476389203:0', data = {'foo'} })

		event, err = sse_conn:receive()
		assert.are.equal(err,'timeout')
		assert.is_nil(event)

		event, err = sse_conn:receive()
		assert.is_nil(err)
		assert.are.same(event,{ event = 'bar', id = '1476389204:0', data = {'bar'} })

		event, err = sse_conn:receive()
		assert.are.equal(err,'EOF')
		assert.is_nil(event)
	end)

	it("ignores ': hi' initial message",function()
		local socket = ngx.socket.tcp.next()

    socket:deliver(
      'HTTP/1.1 200 OK',
      'Content-Type: text/event-stream; charset=utf-8',
      '',
      ': hi',
      '',
      'event: foo',
      'id: 1476389203:0',
      'data: foo',
      ''
    )

		local sse_conn, event, res, err

		sse_conn, err = sse:new()

		assert.is_nil(err)
		assert(sse_conn)

		res, err = sse_conn:request_uri('http://some-server.com/some/path')

		assert.is_nil(err)
		assert(sse_conn:headers_check_response(res))

		event, err = sse_conn:receive()
		assert.is_nil(err)
		assert.are.same(event,{ event = 'foo', id = '1476389203:0', data = {'foo'} })

		event, err = sse_conn:receive()
		assert.are.equal(err,'EOF')
		assert.is_nil(event)
	end)
end)
