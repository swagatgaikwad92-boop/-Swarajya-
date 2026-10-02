extends RefCounted
## Loads JSON data files. All game content lives in res://data/*.json.

static func load_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		return null
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open data file: " + path)
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("Invalid JSON in: " + path)
	return parsed
