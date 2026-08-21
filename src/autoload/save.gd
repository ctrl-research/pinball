extends Node
## Everything that outlives the process (autoload "Save").
##
## Two separate files, because they have different lifetimes and different
## failure modes. `settings.cfg` is preferences and should survive everything.
## `run.save` is one run in progress and is deleted the moment that run ends --
## a stale run file is worse than none, because it offers to continue something
## that is already over.
##
## Both are `ConfigFile` rather than JSON: it round-trips Godot's own types
## (including Vector2 and typed containers' contents) without a schema, and a
## corrupt section fails to parse loudly instead of loading as null.

const SETTINGS_PATH := "user://settings.cfg"
const RUN_PATH := "user://run.save"

## Bumped when the saved shape changes in a way that cannot be read by the
## loader. A run from an older build is discarded rather than half-read: this is
## a game, and the cost of dropping one in-progress run is far below the cost of
## restoring one into a state the rules no longer describe.
const RUN_FORMAT := 1


# --- Settings -----------------------------------------------------------------


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "crt", Crt.enabled)
	cfg.save(SETTINGS_PATH)


## Applied rather than returned: there is one consumer of each setting and
## handing back a dictionary for the caller to unpack invites a second copy of
## the defaults.
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	Crt.enabled = bool(cfg.get_value("video", "crt", true))


# --- The run in progress ------------------------------------------------------


func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


func save_run() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "format", RUN_FORMAT)
	var data := Run.to_dict()
	for key in data:
		cfg.set_value("run", key, data[key])
	cfg.save(RUN_PATH)


## True if a run was restored. False leaves `Run` untouched, so the caller can
## fall through to starting a fresh one.
func load_run() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(RUN_PATH) != OK:
		return false
	if int(cfg.get_value("meta", "format", 0)) != RUN_FORMAT:
		clear_run()
		return false
	var data := {}
	for key in cfg.get_section_keys("run"):
		data[key] = cfg.get_value("run", key)
	Run.from_dict(data)
	return true


func clear_run() -> void:
	if has_run():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
		# globalize_path does not resolve user:// on every platform, so fall
		# back to the virtual path -- one of the two always works and removing a
		# file that is already gone is harmless.
		if has_run():
			DirAccess.remove_absolute(RUN_PATH)
