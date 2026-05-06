@tool
extends EditorPlugin

var dock: Control

func _enter_tree():
	var script = load("res://addons/character_wizard/wizard_dock.gd")
	if script == null:
		push_error("[Character Wizard] 无法加载 wizard_dock.gd，请检查文件是否存在")
		return

	dock = Control.new()
	dock.set_script(script)
	dock.setup(get_editor_interface())
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree():
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
