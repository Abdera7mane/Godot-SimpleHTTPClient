tool
class_name HTTPResponse

# warning-ignore-all:shadowed_variable

var error: int
var code: int
var headers: PoolStringArray
var body: PoolByteArray

func _init(error: int = 0, code: int = 0, headers: PoolStringArray = [], body: PoolByteArray = []) -> void:
	self.error = error
	self.code = code
	self.headers = headers
	self.body = body

func successful() -> bool:
	return error == OK
