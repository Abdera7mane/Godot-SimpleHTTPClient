tool

# warning-ignore-all:return_value_discarded

class_name HTTPConnectionPool

signal request_completed(response, client)

const DEFAULT_MIN: int = 1
const DEFAULT_MAX: int = IP.RESOLVER_MAX_QUERIES

var clients: Array

var active: int

var max_clients: int
var min_clients: int

var idle_timeout: int setget set_idle_timeout

# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
func _init(min_clients: int = DEFAULT_MIN, max_clients: int = DEFAULT_MAX, idle_timeout: int = 10_000) -> void:
	self.min_clients = min_clients
	self.max_clients = max_clients
	self.idle_timeout = idle_timeout
	
	for i in min_clients:
		_append_client()

func request_async(
	url: String, headers: Dictionary = {}, validate_ssl: bool = true,
	method: int = HTTPClient.METHOD_GET, body: PoolByteArray = []
) -> HTTPResponse:
	var client: SimpleHTTPClient
	var state = _find_client()
	
	if state is GDScriptFunctionState:
		client = yield(state, "completed")
	else:
		client = state
	
	active += 1
	reference()
	state = client.request_async(url, headers, validate_ssl, method, body)
	var response: HTTPResponse = yield(state, "completed")
	emit_signal("request_completed", response, client)
	unreference()
	active -= 1
	
	return response

func set_idle_timeout(value: int) -> void:
	idle_timeout = int(max(0, value))
	
	var total_clients: int = clients.size()
	if total_clients < min_clients:
		return
	
	for i in range(min_clients, total_clients):
		var client: SimpleHTTPClient = clients[i]
		client.idle_timeout = idle_timeout

func _find_client() -> SimpleHTTPClient:
	var client: SimpleHTTPClient = null
	
	var total_clients: int = clients.size()
	
	if active == max_clients:
		while not client or client.requesting:
			client = yield(self, "request_completed")[1]
	
	if not client and active == total_clients and total_clients < max_clients:
		_append_client()
		client = clients[-1]
	
	if not client:
		for _client in clients:
			if not _client.requesting:
				client = _client
	return client

func _append_client() -> void:
	var client: SimpleHTTPClient = SimpleHTTPClient.new()
	client.keep_alive = true
	if clients.size() >= min_clients:
		client.idle_timeout = idle_timeout
		client.connect("disconnected", self, "_on_client_disonnected", [client])
	clients.append(client)

func _on_request_completed(response: HTTPResponse, client: SimpleHTTPClient) -> void:
	emit_signal("request_completed", response, client)

func _on_client_disonnected(client: SimpleHTTPClient) -> void:
	clients.erase(client)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			for client in clients:
				client.close()
