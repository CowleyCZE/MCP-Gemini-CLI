extends Node

func handle_command(cmd: String, command: Dictionary) -> String:
	match cmd:
		"ui_set_layout":
			return ui_set_layout(command)
		_: 
			return JSON.stringify({"status": "error", "message": "Neznámý 2D příkaz"})

func ui_set_layout(command: Dictionary) -> String:
	var path = command.get("node_path", "")
	var preset_str = command.get("preset", "center")
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(path)
	if not node or not (node is Control):
		return JSON.stringify({"status": "error", "message": "Node není Control (UI)"})
	var preset = Control.PRESET_CENTER
	match preset_str:
		"top_left": preset = Control.PRESET_TOP_LEFT
		"top_right": preset = Control.PRESET_TOP_RIGHT
		"bottom_left": preset = Control.PRESET_BOTTOM_LEFT
		"bottom_right": preset = Control.PRESET_BOTTOM_RIGHT
		"center_left": preset = Control.PRESET_CENTER_LEFT
		"center_top": preset = Control.PRESET_CENTER_TOP
		"center_right": preset = Control.PRESET_CENTER_RIGHT
		"center_bottom": preset = Control.PRESET_CENTER_BOTTOM
		"center": preset = Control.PRESET_CENTER
		"full_rect": preset = Control.PRESET_FULL_RECT
		"top_wide": preset = Control.PRESET_TOP_WIDE
		"bottom_wide": preset = Control.PRESET_BOTTOM_WIDE
		"left_wide": preset = Control.PRESET_LEFT_WIDE
		"right_wide": preset = Control.PRESET_RIGHT_WIDE
		"v_center_wide": preset = Control.PRESET_VCENTER_WIDE
		"h_center_wide": preset = Control.PRESET_HCENTER_WIDE
	node.set_anchors_preset(preset)
	return JSON.stringify({"status": "ok", "message": "Layout nastaven na " + preset_str})
