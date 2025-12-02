extends Node

func handle_command(cmd: String, command: Dictionary) -> String:
	match cmd:
		"create_node_2d":
			return await create_node_2d(command)
		"set_transform_2d":
			return set_transform_2d(command)
		"get_info_2d":
			return get_info_2d(command)
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

func create_node_2d(command: Dictionary) -> String:
	var node_type = command.get("type", "Node2D")
	var node_name = command.get("name", "NewNode2D")
	var parent_path = str(command.get("parent", ""))
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	var new_node = null
	if ClassDB.can_instantiate(node_type):
		new_node = ClassDB.instantiate(node_type)
	if not new_node:
		return JSON.stringify({"status": "error", "message": "Neplatný typ"})
	new_node.name = node_name
	var parent = root
	if parent_path != "":
		parent = root.get_node_or_null(parent_path)
		if not parent:
			new_node.free()
			return JSON.stringify({"status": "error", "message": "Parent nenalezen"})
	parent.add_child(new_node)
	new_node.owner = root
	await get_tree().process_frame
	if is_instance_valid(new_node):
		return JSON.stringify({"status": "ok", "message": "Node vytvořen", "path": str(new_node.get_path())})
	else:
		return JSON.stringify({"status": "error", "message": "Node byl vytvořen, ale ihned zmizel"})

func set_transform_2d(command: Dictionary) -> String:
	var path = command.get("path", "")
	var pos_arr = command.get("position", null)
	var rot_deg = command.get("rotation_degrees", null)
	var scale_arr = command.get("scale", null)
	var root = EditorInterface.get_edited_scene_root()
	var node = root.get_node_or_null(path)
	if not node:
		return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	if pos_arr != null and typeof(pos_arr) == TYPE_ARRAY and pos_arr.size() >= 2:
		node.position = Vector2(float(pos_arr[0]), float(pos_arr[1]))
	if rot_deg != null:
		node.rotation_degrees = float(rot_deg)
	if scale_arr != null and typeof(scale_arr) == TYPE_ARRAY and scale_arr.size() >= 2:
		node.scale = Vector2(float(scale_arr[0]), float(scale_arr[1]))
	return JSON.stringify({"status": "ok", "message": "Transformace nastavena"})

func get_info_2d(command: Dictionary) -> String:
	var path = command.get("path", "")
	var root = EditorInterface.get_edited_scene_root()
	var node = root.get_node_or_null(path)
	if not node:
		return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	var info = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path())
	}
	if node is Node2D:
		info["position"] = [node.position.x, node.position.y]
		info["rotation_degrees"] = node.rotation_degrees
		info["scale"] = [node.scale.x, node.scale.y]
	elif node is Control:
		info["position"] = [node.position.x, node.position.y]
		info["size"] = [node.size.x, node.size.y]
	return JSON.stringify({"status": "ok", "info": info})
