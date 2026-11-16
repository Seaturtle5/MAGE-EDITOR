class_name EditorPrefs
extends RefCounted
## Settings remembered on this computer, never in a pack.

static func path() -> String:
	return OS.get_user_data_dir().path_join("preferences.cfg")

static func read(section: String, key: String, fallback: Variant) -> Variant:
	var config := ConfigFile.new()
	config.load(path())
	return config.get_value(section, key, fallback)

static func write(section: String, key: String, value: Variant) -> bool:
	var config := ConfigFile.new()
	config.load(path())
	config.set_value(section, key, value)
	return config.save(path()) == OK
