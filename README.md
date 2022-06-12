# Simple HTTP Client

Mostly inspired from [HTTPRequest](https://docs.godotengine.org/en/3.5/classes/class_httprequest.html) node's implementation, brings extra features and improvements. (WIP)

## Why not just use **HTTPRequest** node ?

While I understand that `HTTPRequest` requires the [SceneTree](https://docs.godotengine.org/en/3.5/classes/class_scenetree.html) loop to function which is why it is in a form of a [Node](https://docs.godotengine.org/en/3.5/classes/class_node.html), there are several reasons to avoid it:

1. It does not reuse [HTTPClient](https://docs.godotengine.org/en/3.4/classes/class_httprequest.html) between requests.
2. It closes and opens a new connection for each redirection even if the redirect `host:port` is the same.
3. No way of keeping an alive connection.
4. [Do not use Node for everything](https://docs.godotengine.org/en/3.5/tutorials/best_practices/node_alternatives.html).

Ok cool, but shouldn't some of these be reported to [Godot's issue tracker](https://github.com/godotengine/godot/issues) ? Yes, I agree however I am not interested in using `HTTPRequest` in most cases, or at least until it gets a replacement with a more elegant implementation.

# Features

1. Keep-Alive connections, which reduces the overhead when sending requests to the same server.
2. HTTP connection pool, to send multiple requests by reusing pre-instantiated clients.
3. Automatic [gzip](https://en.wikipedia.org/wiki/Gzip) decompression.
4. Idle connection timeout.
5. Download streaming.

## Examples

### **HTTP GET** method:
```gdscript
var client := SimpleHTTPClient.new()

var url := "https://httpbin.org/headers"
var validate_ssl := true
var method := HTTPClient.METHOD_GET
var headers := {
	"Name": "Value"
}

var response: HTTPResponse = yield(client.request_async(url, headers, validate_ssl, method), "completed")

if response.successful():
	print(response.body.get_string_from_utf8())
```
if you are willing to reuse the same client to request to the same server, set `keep_alive` to `true`, to close the connection call `close()` (automatically called when the instance is freed)

### Streaming:

Requesting large files/payloads must be streamed. The following is an example to download Godot `3.4.4.stable` source and save it to a file:
```gdscript
var client := SimpleHTTPClient.new()
client.stream = true

var url: String = "https://downloads.tuxfamily.org/godotengine/3.4.4/godot-3.4.4-stable.tar.xz"

var file := File.new()
if file.open(url.get_file(), File.WRITE) != OK:
	push_error("Failed opening file")
	return

client.request_async(url)

print("Downloading...")

while client.requesting:
	var stream: Array = yield(client, "response_stream")
	var chunk: PoolByteArray = stream[1]
	file.store_buffer(chunk)

print("Completed")

file.close()
```