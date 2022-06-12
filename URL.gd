tool
class_name URL

static func parse_url(url: String) -> Dictionary:
	var use_ssl: bool = url.begins_with("https://")
	var host: String
	var path: String
	var port: int = -1
	
	url = url.trim_prefix("http://").trim_prefix("https://")
	
	var path_delimiter: int = url.find("/")
	var port_delimiter: int
	
	path = url.substr(path_delimiter)
	if path.empty():
		path = "/"
	
	var has_port: bool
	
	# IPv6
	if url[0] == "[":
		var end: int = url.find("]")
		if end != -1:
			port_delimiter = url.find(":", end)
			has_port = port_delimiter != -1 and port_delimiter < path_delimiter
			host = url.substr(0, end + 1 if not has_port else port_delimiter)
	# IPv4
	else:
		port_delimiter = url.find(":")
		has_port = port_delimiter != -1 and port_delimiter < path_delimiter
		host = url.substr(0, path_delimiter if not has_port else port_delimiter)
	
	if has_port:
		port = url.substr(port_delimiter, path_delimiter).to_int()
	
	return {
		host = host,
		port = port,
		path = path,
		use_ssl = use_ssl
	}

static func must_reconnect(old: Dictionary, new: Dictionary) -> bool:
	return (old.empty() or new.empty())\
			or not old.host.empty()\
			and (old.host != new.host or old.use_ssl != new.use_ssl)\
			or old.port != new.port
