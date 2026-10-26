extends RefCounted
## Tiny assertion collector shared by the test scripts.
var failures: Array[String] = []
var passed := 0
var name := ""


func _init(test_name: String) -> void:
	name = test_name


func ok(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(message)
		printerr("FAIL %s: %s" % [name, message])


func equal(actual: Variant, expected: Variant, message: String) -> void:
	ok(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


## Print the summary line and return the process exit code.
func finish() -> int:
	if failures.is_empty():
		print("%s_PASS: %d checks" % [name, passed])
		return 0
	print("%s_FAIL: %d of %d checks failed" % [name, failures.size(), failures.size() + passed])
	return 1
