extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd
## Optional filter: -- --filter=hex   (runs only files whose path contains "hex")
## Exit code is non-zero if any test fails, so CI can use it.


func _initialize() -> void:
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.trim_prefix("--filter=")

	var files := _find_tests("res://tests")
	var passed := 0
	var failed := 0
	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
		var script: GDScript = load(path)
		if script == null:
			printerr("Could not load %s" % path)
			failed += 1
			continue
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var method_name: String = m["name"]
			if method_name.begins_with("test_") and method_name not in methods:
				methods.append(method_name)
		for method_name in methods:
			var instance: TestCase = script.new()
			instance._current = "%s::%s" % [path.get_file(), method_name]
			instance.before_each()
			instance.call(method_name)
			if instance.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for f in instance.failures:
					printerr("  FAIL %s" % f)

	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _find_tests(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_find_tests(dir_path.path_join(sub)))
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			out.append(dir_path.path_join(f))
	out.sort()
	return out
