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

	if path_delimiter == -1:
		path_delimiter = url.length()
	
	path = url.substr(path_delimiter)
	if path.empty():
		path = "/"
	
	var has_port: bool
	var host_length: int

	# IPv6
	if url[0] == "[":
		var end: int = url.find("]")
		if end == -1:
			port_delimiter = url.find(":", end)
			has_port = port_delimiter != -1 and port_delimiter < path_delimiter
			host_length = end + 1 if not has_port else port_delimiter
	# IPv4
	else:
		port_delimiter = url.find(":")
		has_port = port_delimiter != -1 and port_delimiter < path_delimiter
		host_length = path_delimiter if not has_port else port_delimiter
	
	host = url.substr(0, host_length)

	if has_port:
		var port_length: int =  path_delimiter - port_delimiter \
		                     if path_delimiter > 0 \
	                       else url.length() - port_delimiter

		port = url.substr(port_delimiter, port_length).to_int()
	
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

