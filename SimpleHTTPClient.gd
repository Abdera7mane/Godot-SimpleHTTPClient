# Reference: https://github.com/godotengine/godot/blob/master/scene/main/http_request.cpp

tool
class_name SimpleHTTPClient

enum {
	ERR_SSL_HANDSHAKE_ERROR = 49,
	ERR_NO_RESPONSE,
	ERR_REDIRECT_LIMIT_REACHED,
	ERR_CHUNKED_BODY_SIZE_MISMATCH
	ERR_BODY_SIZE_LIMIT_EXCEEDED
}

var http_client: HTTPClient = HTTPClient.new()
var max_redirects: int = 8
var read_chunk_size: int = 65536
var body_size_limit: int = -1
var requesting: bool

# Sends an HTTP request asynchronously and returns an HTTPResponse object
# This function is a coroutine and you must 'yield()' in order to get the response
#
# url: the address, specifying the protocol is optional however if a server
# requires HTTPS then adding "https://" at the start of the url is necessary
#
# headers: HTTP request headers
#
# validate_ssl:  weather to check the SSL identity of the host 
#
# method: HTTP request method

# body: request's body as a byte array
func request_async(url: String, headers: PoolStringArray = [], validate_ssl: bool = true, method: int = HTTPClient.METHOD_GET, body: PoolByteArray = []) -> HTTPResponse:
	if requesting:
		push_error("Already performing an HTTP request")
		return null
	var connection: HTTPConenction = HTTPConenction.new()
	connection.open({
		client = http_client,
		max_redirects = max_redirects,
		read_chunk_size = read_chunk_size,
		body_size_limit = body_size_limit,
		url = URL.new(url),
		headers = headers,
		validate_ssl = validate_ssl,
		method = method,
		body = body
	})
	requesting = true
	var response: Array = yield(connection, "finished")
	connection.call_deferred("free")
	requesting = false
	return HTTPResponse.new(
		response[0],
		response[1],
		response[2],
		response[3]
	)

class HTTPConenction extends Object:
	
	signal finished(error, response_code, headers, body)
	
	var _thread: Thread
	var client: HTTPClient
	var url: URL
	var request_path: String
	var headers: PoolStringArray
	var max_redirects: int
	var body_size_limit
	var validate_ssl: bool

	var cancelled: bool
	var response: PoolByteArray
	var response_headers: PoolStringArray
	var response_code: int
	var redirections: int
	var requesting: bool
	var request_sent: bool
	var got_response: bool

	func open(configuration: Dictionary) -> void:
		if requesting:
			push_error("ALready performing a request")
			return
		client = configuration["client"]
		url = configuration["url"]
		max_redirects = configuration["max_redirects"]
		body_size_limit = configuration["body_size_limit"]
		headers = configuration["headers"]
		validate_ssl = configuration["validate_ssl"]
		
		client.blocking_mode_enabled = true
		client.read_chunk_size = configuration["read_chunk_size"]
		_thread = Thread.new()
		var error = _thread.start(self, "_connection_loop", configuration)
		if error != OK:
			_close(error, 0, PoolStringArray(), PoolByteArray())
			return
		requesting = true
	
	func cancel() -> void:
		cancelled = true
		if not requesting:
			return
		if _thread.is_active():
			_thread.wait_to_finish()
		
		response = []
		response_headers = []
		response_code = 0
		redirections = 0
		requesting = false
		request_sent = false
		got_response = false
		client.close()

	func _connection_loop(configuration: Dictionary) -> void:
		var method = configuration["method"]
		var body = configuration["body"]

		var error: int = client.connect_to_host(url.host, url.port, url.use_ssl(), validate_ssl)
		if  error != OK:
			call_deferred("_close", error, 0, PoolStringArray(), PoolByteArray())
			return
		
		request_path = url.get_full_path()
		
		while not cancelled:
			var exit: bool = _update_connection(method, body)
			if exit:
				break
			OS.delay_msec(16)
	
	func _update_connection(method: int, request_data: PoolByteArray) -> bool:
		var error: int = OK
		match client.get_status():
			HTTPClient.STATUS_DISCONNECTED, HTTPClient.STATUS_CANT_CONNECT:
				error = ERR_CANT_CONNECT
			HTTPClient.STATUS_RESOLVING,\
			HTTPClient.STATUS_CONNECTING,\
			HTTPClient.STATUS_REQUESTING:
				# warning-ignore:return_value_discarded	
				client.poll()
			HTTPClient.STATUS_CANT_RESOLVE:
				error = ERR_CANT_RESOLVE
			HTTPClient.STATUS_CONNECTED:
				if request_sent:
					if not got_response:
						var _error: int = _handle_response()
						if _error != ERR_SKIP:
							error = _error
						else:
							call_deferred("_close", OK, response_code, response_headers, PoolByteArray())
							return true
					if client.get_response_body_length() < 0:
						call_deferred("_close", OK, response_code, response_headers, response)
						return true
					call_deferred("_close", ERR_CHUNKED_BODY_SIZE_MISMATCH, response_code, response_headers, PoolByteArray())
					return true
				else:
					error = client.request_raw(method, request_path, headers, request_data)
					request_sent = true
			HTTPClient.STATUS_BODY:
				if not got_response:
					var _error: int = _handle_response()
					if _error != ERR_SKIP:
						error = _error
						return error != OK

					var body_length: int = client.get_response_body_length()
					if not client.is_response_chunked() and body_length == 0:
						call_deferred("_close", OK, response_code, response_headers, PoolByteArray())
						return true
					if body_size_limit >= 0 and body_length > body_size_limit:
						call_deferred("_close", ERR_BODY_SIZE_LIMIT_EXCEEDED, response_code, response_headers, PoolByteArray())
						return true
					
				var body_length: int = client.get_response_body_length()
				# warning-ignore:return_value_discarded
				client.poll()
				if client.get_status() != HTTPClient.STATUS_BODY:
					return false
				
				var chunk: PoolByteArray = client.read_response_body_chunk()
				if chunk.size() > 0:
					response.append_array(chunk)
				
				if body_size_limit >= 0 and response.size() > body_length:
					call_deferred("_close", ERR_BODY_SIZE_LIMIT_EXCEEDED, response_code, response_headers, PoolByteArray())
					return true
				
				if body_length >= 0:
					if response.size() == body_length:
						call_deferred("_close", OK, response_code, response_headers, response)
						return true
				if client.get_status() == HTTPClient.STATUS_DISCONNECTED:
					call_deferred("_close", OK, response_code, response_headers, response)
					return true
				return false
			HTTPClient.STATUS_CONNECTION_ERROR:
				error = ERR_CONNECTION_ERROR
			HTTPClient.STATUS_SSL_HANDSHAKE_ERROR:
				error = ERR_SSL_HANDSHAKE_ERROR
		var exit: bool = error != OK
		if exit:
			call_deferred("_close", error, 0, PoolStringArray(), PoolByteArray())
		return exit
	
	func _close(error: int, _response_code: int, _headers: PoolStringArray, body: PoolByteArray) -> void:
		cancel()
		emit_signal("finished", error, _response_code, _headers, body)
	
	func _handle_response() -> int:
		if not client.has_response():
			return ERR_NO_RESPONSE
		
		got_response = true
		response_code = client.get_response_code()
		response_headers = client.get_response_headers()
			
		match response_code:
			HTTPClient.RESPONSE_MOVED_PERMANENTLY, HTTPClient.RESPONSE_FOUND:
				if max_redirects >= 0 and redirections >= max_redirects:
					call_deferred("_close", ERR_REDIRECT_LIMIT_REACHED, response_code, response_headers, PoolByteArray())
					return ERR_REDIRECT_LIMIT_REACHED
				
				var redirect_url: String
				
				var redirection_header: String = "Location: "
				for header in response_headers:
					if header.findn(redirection_header) != -1:
						redirect_url = header.substr(redirection_header.length() - 1, header.length()).strip_edges()
						break
				
				if not redirect_url.empty():
					client.close()
					if redirect_url.begins_with("http"):
						url.parse_url(redirect_url)
						request_path = url.get_full_path()
					else:
						request_path = redirect_url
					
					var error: int = client.connect_to_host(url.host, url.port, url.use_ssl())
					if error == OK:
						redirections += 1
						request_sent = false
						got_response = false
						return OK
		return ERR_SKIP
	
	func _notification(what: int) -> void:
		match what:
			NOTIFICATION_PREDELETE:
				if _thread and _thread.is_active():
					_thread.wait_to_finish()
				_thread = null
				url = null
