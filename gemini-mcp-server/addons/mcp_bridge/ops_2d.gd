# res://addons/mcp_bridge/ops_2d.gd
extends RefCounted

# Hlavní vstupní bod pro tento modul
func handle_command(cmd_type: String, command: Dictionary) -> String:
	match cmd_type:
		"create_node_2d": return create_node_2d(command)
		"set_transform_2d": return set_transform_2d(command)
		"get_info_2d": return get_info_2d(command)
		_: return JSON.stringify({"status": "error", "message": "Neznámý 2D příkaz: " + cmd_type})

# --- IMPLEMENTACE FUNKCÍ ---

func create_node_2d(command: Dictionary) -> String:
	var type = command.get("type", "Node2D")
	var name = command.get("name", "New2DNode")
	var parent_path = command.get("parent_path", "")
	
	# Validace, zda jde skutečně o 2D node nebo Control (UI)
	if not ClassDB.is_parent_class(type, "CanvasItem"):
		return JSON.stringify({"status": "error", "message": "Typ '%s' není 2D uzel (CanvasItem)." % type})
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	
	var node = ClassDB.instantiate(type)
	if not node: return JSON.stringify({"status": "error", "message": "Nelze instanciovat " + type})
	node.name = name
	
	# Speciality pro specifické typy
	if node is Sprite2D and command.has("texture_path"):
		var tex = load(command.texture_path)
		if tex: node.texture = tex
		
	if node is Label and command.has("text"):
		node.text = command.text
	
	# Hierarchie
	var parent = edited_scene
	if parent_path != "":
		parent = edited_scene.get_node_or_null(parent_path)
		if not parent:
			node.free()
			return JSON.stringify({"status": "error", "message": "Rodič nenalezen"})
			
	parent.add_child(node)
	node.owner = edited_scene
	
	# Pozice
	if command.has("position"):
		var p = command.position
		node.position = Vector2(p[0], p[1])
		
	return JSON.stringify({"status": "ok", "message": "2D Node vytvořen", "path": str(node.get_path())})

func set_transform_2d(command: Dictionary) -> String:
	var path = command.get("node_path", "")
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(path)
	
	if not node or not (node is Node2D or node is Control):
		return JSON.stringify({"status": "error", "message": "Node2D nenalezen"})
		
	if command.has("position"):
		var p = command.position
		node.position = Vector2(p[0], p[1])
		
	if command.has("rotation"): # Ve stupních
		node.rotation_degrees = float(command.rotation)
		
	if command.has("scale"):
		var s = command.scale
		node.scale = Vector2(s[0], s[1])
		
	return JSON.stringify({"status": "ok", "message": "Transformace nastavena"})

func get_info_2d(command: Dictionary) -> String:
	var path = command.get("node_path", "")
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(path)
	
	if not node or not (node is CanvasItem):
		return JSON.stringify({"status": "error", "message": "Node nenalezen"})
		
	var info = {
		"name": node.name,
		"type": node.get_class(),
		"visible": node.visible,
		"position": [node.position.x, node.position.y]
	}
	
	if node is Node2D:
		info["rotation"] = node.rotation_degrees
		info["scale"] = [node.scale.x, node.scale.y]
		
	return JSON.stringify({"status": "ok", "info": info})