extends SceneTree
## Write the generated solid-colour test pack to a folder, and optionally a zip.
##   tools/godot.sh --headless --script tools/make-test-pack.gd -- FOLDER [ZIP]
const TestPack = preload("res://tests/test_pack.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	TestPack.build(args[0])
	if args.size() > 1:
		TestPack.zip(args[0], args[1])
	print("TEST_PACK_WRITTEN %s" % args[0])
	quit()
