class_name URL

enum Protocols {
	HTTP,
	HTTPS
}

const PROTOCOL_STRINGS: Dictionary = {
	Protocols.HTTP: "http://",
	Protocols.HTTPS: "https://"
}

const DEFAULT_PORTS: Dictionary = {
	Protocols.HTTP: 80,
	Protocols.HTTPS: 443
}

var host: String
var path: String
var query: String
var fragment: String
var port: int
var protocol: int

func _init(url: String = "") -> void:
	if url.empty():
		return
	parse_url(url)

func get_file_name() -> String:
	return path.get_file()

func get_file_extension() -> String:
	return path.get_extension()

func get_full_path() -> String:
	var full_path: String = "/" + path.strip_edges()
	if not query.empty():
		full_path += "?" + query.strip_edges()
	if not fragment.empty():
		full_path += "#" + fragment.strip_edges()
	return full_path

func parse_url(url: String) -> void:
	url = url.strip_edges()
	var regex_match: RegExMatch = _get_url_regex().search(url)
	if not regex_match:
		push_error("Invalid URL format")
		return
	
	protocol = Protocols.HTTPS if regex_match.get_string("protocol") == "https://" else Protocols.HTTP
	host = regex_match.get_string("host")
	port = int(regex_match.get_string("port")) if regex_match.names.has("port") else DEFAULT_PORTS[protocol]
	path = regex_match.get_string("path")
	query = regex_match.get_string("query")
	fragment = regex_match.get_string("fragment")

func use_ssl() -> bool:
	return protocol == Protocols.HTTPS

func _get_url_regex() -> RegEx:
	var script: Script = get_script()
	var regex: RegEx
	if script.has_meta("url_regex"):
		regex = script.get_meta("url_regex")
	else:
		regex = get_url_regex()
		script.set_meta("url_regex", regex)
	return regex

func _to_string() -> String:
	var url: String = PROTOCOL_STRINGS[protocol] + host.strip_edges()
	var default_port: int = DEFAULT_PORTS[protocol]
	if port < 1:
		port = default_port
	if default_port != port:
		url += ":" + str(port)
	return url + get_full_path()

static func get_url_regex() -> RegEx:
	var regex = RegEx.new()
	var pattern: String = "(?<protocol>http[s]?://)?"\
						+ "(?<host>((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)+[A-Za-z]{2,6})"\
						+ "(:(?<port>\\d{1,5}))?"\
						+ "(/(?<path>([^#?\\s]/?)*))?"\
						+ "(\\?(?<query>[a-zA-Z0-9_\\-.~:@&=+$,%]+))?"\
						+ "(#(?<fragment>.*))?"
	assert(regex.compile("^%s$" % pattern) == OK, "Failed to compile regex pattern: %s" % pattern)
	return regex
