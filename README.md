# Simple HTTP Client

This is simply a port of the built-in [HTTPRequest](https://docs.godotengine.org/en/3.4/classes/class_httprequest.html#class-httprequest) node's implementation, modified to work independently from the SceneTree

## Example

**HTTP GET** method:
```gdscript
var client := SimpleHTTPClient.new()

var url := "https://httpbin.org/headers"
var validate_ssl := true
var method := HTTPClient.METHOD_GET
var headers := PoolStringArray()

var response: HTTPResponse = yield(client.request_async(url, headers, validate_ssl, method), "completed")

if response.successful():
	print(response.body.get_string_from_utf8())
```

**HTTP POST** method:
```gdscript
var client := SimpleHTTPClient.new()

var url := "https://httpbin.org/post" # will echo back our "POST" data
var validate_ssl := true
var method := HTTPClient.METHOD_POST
var headers := PoolStringArray()
var body: PoolByteArray = "Hello world".to_utf8()

var response: HTTPResponse = yield(client.request_async(url, headers, validate_ssl, method, body), "completed")

if response.successful():
	print(response.body.get_string_from_utf8())
```