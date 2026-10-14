extends RefCounted
## Only explicit completion may authorize a successful headless test run.


static func prepare(tree: SceneTree) -> bool:
	var case_name: String = tree.get_script().resource_path.get_file().get_basename()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting(
		"application/config/custom_user_dir_name",
		"ImmivioTests/%s/%d-%d" % [case_name, OS.get_process_id(), Time.get_ticks_usec()]
	)
	if DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Cannot create isolated test user data")
		finish(tree, 1)
		return false
	print("Test user data: ", OS.get_user_data_dir())
	return true


static func finish(tree: SceneTree, exit_code: int) -> void:
	print(
		(
			"IMMIVIO_TEST_RESULT "
			+ (
				JSON
				. stringify(
					{
						"script": tree.get_script().resource_path,
						"exit_code": exit_code,
					}
				)
			)
		)
	)
	tree.quit(exit_code)
