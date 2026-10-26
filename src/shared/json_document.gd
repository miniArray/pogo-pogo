extends RefCounted
## Reads player-supplied JSON against a committed JSON Schema (2020-12 subset).
##
## Every player-supplied JSON input, course or asset pack, goes through the same gate:
## a byte cap and nesting cap before parsing, valid UTF-8, the schema's
## const/enum/object/array/integer/string rules with unknown fields rejected,
## then integral floats folded to ints. Callers add their own semantic checks.
## Problems are dictionaries {kind, path, message}; success is {kind: "ready",
## data}.
const MAX_DEPTH := 16


## Parse `bytes` and validate it against the schema file at `schema_path`.
static func read(bytes: PackedByteArray, schema_path: String, max_bytes: int) -> Dictionary:
	if bytes.size() > max_bytes:
		return problem("size", "$", "Maximum file size is %d bytes." % max_bytes)
	if not utf8(bytes):
		return problem("encoding", "$", "Use valid UTF-8 JSON.")
	var text := bytes.get_string_from_utf8()
	var depth := 0
	var quoted := false
	var escaped := false
	for character in text:
		if quoted:
			if escaped:
				escaped = false
			elif character == "\\":
				escaped = true
			elif character == '"':
				quoted = false
		elif character == '"':
			quoted = true
		elif character in ["[", "{"]:
			depth += 1
			if depth > MAX_DEPTH:
				return problem("depth", "$", "Maximum nesting is %d." % MAX_DEPTH)
		elif character in ["]", "}"]:
			depth -= 1
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return problem(
			"json", "$", "Line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(schema_path))
	var error := validate(parser.data, schema, "$", schema)
	if not error.is_empty():
		return error
	return {"kind": "ready", "data": integers(parser.data)}


## Load a schema file once so callers validating fragments share the root.
static func schema_at(schema_path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(schema_path))


static func problem(kind: String, path: String, message: String) -> Dictionary:
	# Rejected input may contain megabyte-long keys; do not turn that into UI layout.
	return {"kind": kind, "path": path.left(256), "message": message.left(512)}


static func schema_equal(value: Variant, expected: Variant) -> bool:
	# JSON numbers compare by value. Booleans and containers are not numbers;
	# Godot's cross-type scalar/container operators can throw instead of returning false.
	if typeof(value) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) in [TYPE_INT, TYPE_FLOAT]:
		return float(value) == float(expected)
	return typeof(value) == typeof(expected) and value == expected


## Validate `value` against `schema`. `root` resolves local `$ref`s of the
## form `#/$defs/name`; pass the document root, or omit for a self-contained
## schema.
static func validate(
	value: Variant, schema: Dictionary, path: String, root: Dictionary = {}
) -> Dictionary:
	if schema.has("$ref"):
		var target := str(schema["$ref"])
		if not target.begins_with("#/$defs/") or not root.get("$defs", {}).has(target.substr(8)):
			return problem("schema", path, "Schema reference %s is not defined." % target)
		return validate(value, root["$defs"][target.substr(8)], path, root)
	if schema.has("const") and not schema_equal(value, schema.const):
		return problem("schema", path, "Expected %s." % str(schema.const))
	if schema.has("enum") and not schema.enum.any(func(option): return schema_equal(value, option)):
		return problem(
			"schema", path, "Unsupported selection; expected one of %s." % str(schema.enum)
		)
	match str(schema.get("type", "")):
		"object":
			if not value is Dictionary:
				return problem("schema", path, "Expected an object.")
			for key in schema.get("required", []):
				if not value.has(key):
					return problem("schema", path + "." + key, "Required field is missing.")
			var properties: Dictionary = schema.get("properties", {})
			var extra: Variant = schema.get("additionalProperties", false)
			for key in value:
				if properties.has(key):
					var error := validate(value[key], properties[key], path + "." + key, root)
					if not error.is_empty():
						return error
				elif extra is Dictionary:
					var error := validate(value[key], extra, path + "." + key, root)
					if not error.is_empty():
						return error
				elif extra != true:
					return problem("schema", path + "." + key, "Unknown field is not supported.")
		"array":
			if not value is Array:
				return problem("schema", path, "Expected an array.")
			if value.size() < schema.minItems or value.size() > schema.maxItems:
				return problem(
					"schema", path, "Expected %d..%d items." % [schema.minItems, schema.maxItems]
				)
			for index in range(value.size()):
				var error := validate(value[index], schema.items, "%s[%d]" % [path, index], root)
				if not error.is_empty():
					return error
		"integer":
			if (
				typeof(value) not in [TYPE_INT, TYPE_FLOAT]
				or not is_finite(float(value))
				or float(value) != floor(float(value))
			):
				return problem("schema", path, "Expected an integer, not a boolean or fraction.")
			if value < schema.minimum or value > schema.maximum:
				return problem(
					"schema", path, "Expected %d..%d." % [schema.minimum, schema.maximum]
				)
		"boolean":
			if typeof(value) != TYPE_BOOL:
				return problem("schema", path, "Expected true or false.")
		"string":
			if not value is String:
				return problem("schema", path, "Expected a string.")
			var pattern := str(schema.get("pattern", ""))
			if (
				value.length() < int(schema.get("minLength", 0))
				or value.length() > int(schema.get("maxLength", 1 << 30))
				or (
					not pattern.is_empty()
					and RegEx.create_from_string(pattern).search(value) == null
				)
			):
				return problem(
					"schema",
					path,
					str(
						schema.get(
							"description",
							(
								"Use %d..%d characters matching %s."
								% [schema.get("minLength", 0), schema.get("maxLength", 0), pattern]
							)
						)
					)
				)
	return {}


static func integers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = integers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(integers(item))
		return result
	return int(value) if typeof(value) == TYPE_FLOAT else value


static func utf8(bytes: PackedByteArray) -> bool:
	var index := 0
	while index < bytes.size():
		var first := bytes[index]
		var count := 0
		var code := first
		if first >= 0xC2 and first <= 0xDF:
			count = 1
			code &= 31
		elif first >= 0xE0 and first <= 0xEF:
			count = 2
			code &= 15
		elif first >= 0xF0 and first <= 0xF4:
			count = 3
			code &= 7
		elif first >= 128:
			return false
		if index + count >= bytes.size():
			return false
		for offset in range(1, count + 1):
			var byte := bytes[index + offset]
			if byte < 128 or byte > 191:
				return false
			code = (code << 6) | (byte & 63)
		if (
			(count == 2 and code < 2048)
			or (count == 3 and code < 65536)
			or code > 0x10FFFF
			or (code >= 0xD800 and code <= 0xDFFF)
		):
			return false
		index += count + 1
	return true
