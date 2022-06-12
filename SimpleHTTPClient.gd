tool

# warning-ignore-all:return_value_discarded
# warning-ignore-all:unused_signal

class_name SimpleHTTPClient

signal connected()
signal disconnected()
signal request_completed(response)
signal response_stream(response, chunk)

enum {
	ERR_SSL_HANDSHAKE_ERROR = 49,
	ERR_NO_RESPONSE,
	ERR_REDIRECT_LIMIT_REACHED,
	ERR_CHUNKED_BODY_SIZE_MISMATCH
	ERR_BODY_SIZE_LIMIT_EXCEEDED
}

var _connection: HTTPConnection

var http: HTTPClient
var https: String
var requesting: bool

var idle_timeout: int    setget set_idle_timeout, get_idle_timeout
var max_redirects: int   setget set_max_redirects, get_max_redirects
var body_size_limit: int setget set_body_size_limit, get_body_size_limit
var stream: bool         setget enable_stream, is_stream_enabled
var keep_alive: bool

func _init() -> void:
	http = HTTPClient.new()
	http.blocking_mode_enabled = true
	_connection = HTTPConnection.new(http)
	_connection.connect("connected", self, "_on_connected")
	_connection.connect("disconnected", self, "_on_disconnected")
	_connection.connect("response_stream", self, "_on_response_stream")

	self.max_redirects = 8
	self.body_size_limit = -1

func has_connection() -> bool:
	return _connection.has_connection()

# Sends an HTTP request asynchronously and returns an HTTPResponse object
# This function is a coroutine and you must 'yield()' in order to get the response
#
# url: the address, specifying the protocol is optional however if a server
# requires HTTPS then adding "https://" at the start of the url is necessary
#
# headers: a Dictionary of HTTP request headers
#
# validate_ssl: whether to check the SSL identity of the host 
#
# method: HTTP request method
#
# body: request's body as a byte array
#
# Returns an HTTPResponse or null when the instance is already requesting
func request_async(
	url: String, headers: Dictionary = {}, validate_ssl: bool = true,
	method: int = HTTPClient.METHOD_GET, body: PoolByteArray = []
) -> HTTPResponse:
	if not requesting:
		_connection.url = URL.parse_url(url)
		_connection.set_request({
			method = method,
			headers = _dict_headers2array(headers),
			body = body,
		})
		_connection.verify_host = validate_ssl
	else:
		push_error("Already performing an HTTP request")
		return null
		
	requesting = true
	reference()
	if not has_connection():
		_connection.start()
	var response: HTTPResponse = yield(_connection, "request_completed")
	unreference()
	requesting = false
	
	if not keep_alive:
		_connection.close()
	
	emit_signal("request_completed", response)
	
	return response

func set_idle_timeout(value: int) -> void:
	if _print_error('idle_timeout'):
		_connection.idle_timeout = value

func set_max_redirects(value: int) -> void:
	if _print_error('max_redirects'):
		_connection.max_redirects = value

func set_body_size_limit(value: int) -> void:
	if _print_error('body_size_limit'):
		_connection.body_size_limit = value

func enable_stream(value: bool) -> void:
	if _print_error('stream'):
		_connection.stream = value

func get_idle_timeout() -> int:
	return _connection.idle_timeout

func get_max_redirects() -> int:
	return _connection.max_redirects

func get_body_size_limit() -> int:
	return _connection.body_size_limit

func is_stream_enabled() -> bool:
	return _connection.stream

func close() -> void:
	_connection.close()

func _print_error(property: String) -> bool:
	if requesting:
		push_error("Can not set '%s' while requesting" % property)
		return false
	return true

func _on_connected() -> void:
	emit_signal("connected")

func _on_disconnected() -> void:
	emit_signal("disconnected")

func _on_response_stream(response: HTTPResponse, chunk: PoolByteArray) -> void:
	call_deferred("emit_signal", "response_stream", response, chunk)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			_connection.close()
			_connection.call_deferred("free")

static func _dict_headers2array(headers: Dictionary) -> PoolStringArray:
	var array: PoolStringArray = []
	for header in headers:
		array.append(header + ": " + headers[header])
	return array

class HTTPConnection extends Object:
	signal connected()
	signal disconnected()
	signal request_completed(response)
	signal response_stream(response, chunk)
	
	var _thread: Thread
	var _mutex: Mutex
	var _request: Dictionary setget set_request
	var _sent_request: bool
	var _got_response: bool
	var _reset_response: bool
	var _skip_body: bool
	var _responded: bool
	var _response_length: int
	var _redirections: int
	var _next_timeout: int
	
	var http: HTTPClient
	var url: Dictionary setget set_url
	var connected: bool
	
	var verify_host: bool
	var idle_timeout: int
	var max_redirects: int
	var body_size_limit: int
	var stream: bool
	
	func _init(client: HTTPClient) -> void:
		_thread = Thread.new()
		_mutex = Mutex.new()
		http = client
	
	func has_connection() -> bool:
		return http.get_status() != HTTPClient.STATUS_DISCONNECTED
	
	func get_request() -> Dictionary:
		_mutex.lock()
		var request: Dictionary = _request
		_mutex.unlock()
		return request
	
	func get_url() -> Dictionary:
		_mutex.lock()
		var _url: Dictionary = url
		_mutex.unlock()
		return _url
	
	func set_request(data: Dictionary) -> void:
		_mutex.lock()
		_request = data
		_mutex.unlock()
	
	func set_url(new_url: Dictionary) -> void:
		_mutex.lock()
		var reconnect: bool = URL.must_reconnect(url, new_url)
		url = new_url
		_mutex.unlock()
		
		if connected and reconnect:
			_connect(url)
	
	func start() -> void:
		_thread.start(self, "_execute")
	
	func close() -> void:
		url.clear()
		http.close()
		if _thread.is_active():
			_thread.wait_to_finish()
			_thread = Thread.new()
		if connected:
			connected = false
			call_deferred("emit_signal", "disconnected")
	
	func _return_response(response: HTTPResponse) -> void:
		_responded = true
		_reset_response = true
		_sent_request = false
		_got_response = false
		_response_length = 0
		_redirections = 0
		
		_mutex.lock()
		_request.clear()
		_mutex.unlock()
		
		if response.body.size() > 0:
			var compressed: PoolByteArray = response.body
			var mode: int = -1
			var buffer_size: int = 0
			var encoding: String
			for header in response.headers:
				if header.to_lower() == "content-encoding":
					encoding = response.headers[header]
					break
			match encoding:
				"gzip", "x-gzip":
					mode = File.COMPRESSION_GZIP
					buffer_size = (compressed[-1] << 24
								| compressed[-2] << 16
								| compressed[-3] << 8
								| compressed[-4])
			if mode > 0:
				response.body = compressed.decompress(buffer_size, mode)
		
		call_deferred("emit_signal", "request_completed", response)
	
	func _stream_chunk(response: HTTPResponse, chunk: PoolByteArray) -> void:
		call_deferred("emit_signal", "response_stream", response, chunk)
	
	func _execute(_data = null) -> void:
		var response: HTTPResponse = HTTPResponse.new()
		var error: int = _connect(url)
		if error != OK:
			response.error = error
			_return_response(response)
			return
		_connection_loop(response)
		
		if has_connection():
			call_deferred("close")
	
	# warning-ignore:shadowed_variable
	func _connect(url: Dictionary) -> int:
		return http.connect_to_host(url.host, url.port, url.use_ssl, verify_host)
	
	func _connection_loop(response: HTTPResponse) -> void:
		while _handle_status(http.get_status(), response):
			if _reset_response:
				response = HTTPResponse.new()
				_reset_response = false
			OS.delay_msec(1)
	
	func _handle_status(status: int, response: HTTPResponse) -> bool:
		var resume: bool = true
		match status:
			HTTPClient.STATUS_DISCONNECTED,\
			HTTPClient.STATUS_CANT_CONNECT:
				response.error = ERR_CANT_CONNECT
				resume = false
			HTTPClient.STATUS_CANT_RESOLVE:
				response.error = ERR_CANT_RESOLVE
				resume = false
			HTTPClient.STATUS_CONNECTION_ERROR:
				response.error = ERR_CONNECTION_ERROR
				resume = false
			HTTPClient.STATUS_SSL_HANDSHAKE_ERROR:
				response.error = ERR_SSL_HANDSHAKE_ERROR
				resume = false
			HTTPClient.STATUS_CONNECTING,\
			HTTPClient.STATUS_RESOLVING,\
			HTTPClient.STATUS_CONNECTED,\
			HTTPClient.STATUS_REQUESTING,\
			HTTPClient.STATUS_BODY:
				http.poll()
				continue
			HTTPClient.STATUS_CONNECTED:
				if not connected:
					set_deferred("connected", true)
					call_deferred("emit_signal", "connected")
				_skip_body = false
				
				var request: Dictionary = self._request
				# warning-ignore:shadowed_variable
				var url: Dictionary = self.url
				
				if not _next_timeout:
					_next_timeout = OS.get_ticks_msec() + idle_timeout
				
				if _sent_request:
					_next_timeout = 0
					if not _got_response:
						response.error = _handle_response(response)
					
					if http.get_response_body_length() < 0:
						_return_response(response)
					else:
						response.error = ERR_CHUNKED_BODY_SIZE_MISMATCH
						_return_response(response)
					
				elif not request.empty():
					_next_timeout = 0
					http.request_raw(request.method, url.path, request.headers, request.body)
					_sent_request = true
					_responded = false
				
				
				resume = not (idle_timeout * _next_timeout > 0 and _next_timeout <= OS.get_ticks_msec())
			HTTPClient.STATUS_BODY:
				if not _got_response:
					response.error = _handle_response(response)
				response.error = _handle_body(response)
		
		if not (resume or _responded):
			_return_response(response)
		
		return resume
	
	func _handle_response(response: HTTPResponse) -> int:
		if not http.has_response():
			_skip_body = true
			_return_response(response)
			return ERR_NO_RESPONSE
		
		_got_response = true
		response.code = http.get_response_code()
		response.headers = http.get_response_headers_as_dictionary()
		
		match response.code:
			HTTPClient.RESPONSE_MOVED_PERMANENTLY, HTTPClient.RESPONSE_FOUND:
				return _handle_redirect(response)
		
		return response.error
	
	func _handle_body(response: HTTPResponse) -> int:
		if http.get_status() != HTTPClient.STATUS_BODY:
			return response.error
		
		var body_length: int = http.get_response_body_length()
		var chunk: PoolByteArray = http.read_response_body_chunk()
		
		if _skip_body:
			return response.error
		
		var chunk_size: int = chunk.size()
		if chunk_size > 0:
			_response_length += chunk_size
			if stream:
				_stream_chunk(response, chunk)
			else:
				response._append_chunk(chunk)
		
		if not http.is_response_chunked() and body_length == 0:
			_return_response(response)
		if body_size_limit >= 0 and body_length > body_size_limit:
			_return_response(response)
			return ERR_BODY_SIZE_LIMIT_EXCEEDED
		
		if body_size_limit >= 0 and _response_length > body_size_limit:
			_return_response(response)
			return ERR_BODY_SIZE_LIMIT_EXCEEDED
		
		if body_length >= 0 and _response_length == body_length:
			_return_response(response)
		return response.error
	
	func _handle_redirect(response: HTTPResponse) -> int:
		var error: int = OK
		if max_redirects >= 0 and _redirections >= max_redirects:
			_skip_body = true
			_return_response(response)
			return ERR_REDIRECT_LIMIT_REACHED
		
		var redirect_url: String = response.get_header("Location")
		
		if redirect_url.empty():
			return error
		
		self.url = URL.parse_url(redirect_url)
		_request.path = url.path
		
		
		_skip_body = true
		_sent_request = false
		if error == OK:
			_redirections += 1
		else:
			_return_response(response)
		
		return error
