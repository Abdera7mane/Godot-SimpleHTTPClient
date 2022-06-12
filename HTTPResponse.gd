tool
class_name HTTPResponse

# warning-ignore-all:shadowed_variable

const RESPONSE_SUCCESS_MAX: int = 299

var error: int
var code: int
var headers: Dictionary
var body: PoolByteArray

func _init(error: int = 0, code: int = 0, headers: Dictionary = {}, body: PoolByteArray = []) -> void:
	self.error = error
	self.code = code
	self.headers = headers
	self.body = body

func successful() -> bool:
	return error == OK and code >= HTTPClient.RESPONSE_OK and code <= RESPONSE_SUCCESS_MAX

func has_header(name: String) -> bool:
	return headers.has(name)

func get_header(name: String) -> String:
	return headers.get(name, "")

func _append_chunk(chunk: PoolByteArray) -> void:
	body.append_array(chunk)
