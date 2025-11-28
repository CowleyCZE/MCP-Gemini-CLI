extends Node

const PORT = 4242
var server: TCPServer
var clients: Array = []
var _process_enabled: bool = true

func _ready():
	server = TCPServer.new()
	var err = server.listen(PORT, "127.0.0.1")
	
	if err == OK:
		print("✓ MCP TCP Server spuštěn na portu %d" % PORT)
	else:
		push_error("✗ Chyba při spuštění serveru: %d" % err)

func _process(_delta):
	if not _process_enabled:
		return
	
	# Příjem nových připojení
	if server.is_connection_available():
		var client = server.take_connection()
		clients.append(client)
		print("✓ Nový klient připojen")
	
	# Zpracování příchozích dat
	var i = 0
	while i < clients.size():
		var client = clients[i]
		
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(i)
			continue
		
		var available = client.get_available_bytes()
		if available > 0:
			var data = client.get_utf8_string(available)
			# Ošetření prázdných dat
			if data.strip_edges().length() > 0:
				var response = process_command(data)
				client.put_data(response.to_utf8_buffer())
		
		i += 1

func process_command(json_string: String) -> String:
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		return JSON.stringify({"status": "error", "message": "Neplatný JSON: " + json.get_error_message()})
	
	var command = json.data
	if typeof(command) != TYPE_DICTIONARY:
		return JSON.stringify({"status": "error", "message": "Příkaz musí být objekt"})
	
	var cmd_type = command.get("cmd", "")
	
	# Dispatcher příkazů
	match cmd_type:
		# --- FILESYSTEM ---
		"list_dir": return list_directory(command)
		"make_dir": return make_directory(command)
		"remove_file": return remove_file(command)
		"rename_file": return rename_file(command)
		
		# --- TERRAIN 3D ---
		"create_terrain": return create_terrain(command)
		"terrain_configure": return terrain_configure(command)
		"terrain_physics": return terrain_physics(command)
		"terrain_rendering": return terrain_rendering(command)
		"terrain_visuals": return terrain_visuals(command)
		"terrain_bake_mesh": return terrain_bake_mesh(command)
		"terrain_get_height": return terrain_get_height(command)
		"set_terrain_collision": return set_terrain_collision(command) # Alias pro zpětnou kompatibilitu
		"terrain_import_heightmap": return terrain_import_heightmap(command)
		
		# --- UZLY (bude v další části) ---
		"create_node": return create_node(command)
		"set_prop": return set_property(command)
		"rename_node": return rename_node(command)
		"delete_node": return delete_node(command)
		"reparent_node": return reparent_node(command)
		"duplicate_node": return duplicate_node(command)
		"get_node_info": return get_node_info(command)
		"set_owner_recursive": return set_owner_recursive(command)
		
		# --- SCÉNY (bude v další části) ---
		"get_scene_tree": return get_scene_tree()
		"save_scene": return save_scene(command)
		"create_scene": return create_scene(command)
		"load_scene": return load_scene(command)
		"add_child_scene": return add_child_scene(command)
		
		# --- MESH A FYZIKA (bude v další části) ---
		"set_mesh": return set_mesh(command)
		"add_collision_shape": return add_collision_shape(command)
		"get_collision_layers": return get_collision_layers()
		"set_collision_layer": return _modify_collision_bitmask(command, "collision_layer")
		"set_collision_mask": return _modify_collision_bitmask(command, "collision_mask")
		
		# --- SKRIPTY (bude v další části) ---
		"create_script": return create_script(command)
		"save_script": return save_script(command)
		"delete_script": return delete_script(command)
		"attach_script": return attach_script(command)
		"detach_script": return detach_script(command)
		"get_script_content": return get_script_content(command)
		
		_: return JSON.stringify({"status": "error", "message": "Neznámý příkaz: " + cmd_type})

# ============================================================================
# FILESYSTEM
# ============================================================================

func list_directory(command: Dictionary) -> String:
	var path = command.get("path", "res://")
	var recursive = command.get("recursive", false)
	var extensions = command.get("extensions", []) # Filtr, např. [".tscn", ".obj"]
	
	var dir = DirAccess.open(path)
	if not dir:
		return JSON.stringify({"status": "error", "message": "Nelze otevřít adresář: " + path})
	
	var files = []
	if recursive:
		files = _scan_dir_recursive(path, extensions)
	else:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				files.append({"name": file_name, "type": "dir", "path": path.path_join(file_name)})
			else:
				var ext = "." + file_name.get_extension()
				if extensions.is_empty() or ext in extensions:
					files.append({"name": file_name, "type": "file", "path": path.path_join(file_name)})
			file_name = dir.get_next()
	
	return JSON.stringify({"status": "ok", "files": files, "base_path": path})

func _scan_dir_recursive(path: String, extensions: Array) -> Array:
	var files = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = path.path_join(file_name)
				if dir.current_is_dir():
					# Přidat složku
					files.append({"name": file_name, "type": "dir", "path": full_path})
					# Rekurze
					files.append_array(_scan_dir_recursive(full_path, extensions))
				else:
					var ext = "." + file_name.get_extension()
					if extensions.is_empty() or ext in extensions:
						files.append({"name": file_name, "type": "file", "path": full_path})
			file_name = dir.get_next()
	return files

func make_directory(command: Dictionary) -> String:
	var path = command.get("path", "")
	var dir = DirAccess.open("res://")
	if dir.make_dir_recursive(path) == OK:
		# Obnovit filesystem editoru
		EditorInterface.get_resource_filesystem().scan()
		return JSON.stringify({"status": "ok", "message": "Složka vytvořena: " + path})
	return JSON.stringify({"status": "error", "message": "Chyba při vytváření složky"})

func rename_file(command: Dictionary) -> String:
	var from_path = command.get("from_path", "")
	var to_path = command.get("to_path", "")
	var dir = DirAccess.open("res://")
	if dir.rename(from_path, to_path) == OK:
		EditorInterface.get_resource_filesystem().scan()
		return JSON.stringify({"status": "ok", "message": "Přejmenováno/Přesunuto"})
	return JSON.stringify({"status": "error", "message": "Chyba při přejmenování"})

func remove_file(command: Dictionary) -> String:
	var path = command.get("path", "")
	var dir = DirAccess.open("res://")
	
	if dir.dir_exists(path):
		# Je to složka
		if dir.remove(path) == OK:
			EditorInterface.get_resource_filesystem().scan()
			return JSON.stringify({"status": "ok", "message": "Složka smazána"})
	elif dir.file_exists(path):
		# Je to soubor
		if dir.remove(path) == OK:
			EditorInterface.get_resource_filesystem().scan()
			return JSON.stringify({"status": "ok", "message": "Soubor smazán"})
			
	return JSON.stringify({"status": "error", "message": "Nelze smazat (neexistuje nebo není prázdná složka)"})

# ============================================================================
# TERRAIN 3D INTEGRATION
# ============================================================================

# 1. Oprava helperu pro terén (Pravděpodobný zdroj chyby na řádku 224)
func _get_terrain(path_input) -> Node:
	# Ošetření vstupu: Pokud je null, udělej z něj prázdný string
	var path: String = str(path_input) if path_input != null else ""
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return null
	
	if path == "":
		return null
		
	var node = edited_scene.get_node_or_null(path)
	# Kontrola třídy (řetězec "Terrain3D")
	if node and node.get_class() == "Terrain3D":
		return node
	return null

func create_terrain(command: Dictionary) -> String:
	# 1. Kontrola existence pluginu
	if not ClassDB.class_exists("Terrain3D"):
		return JSON.stringify({"status": "error", "message": "Plugin 'Terrain3D' není nainstalován (chybí GDExtension)."})

	# 2. Příprava rodiče
	var parent_path_raw = command.get("parent_path")
	var parent_path: String = str(parent_path_raw) if parent_path_raw != null else ""
	var name = command.get("name", "Terrain3D")
	
	# 3. Zpracování cesty k datům (Kritická oprava pro chybu 'Cannot open directory')
	var storage_path_raw = command.get("storage_path")
	var data_dir: String = str(storage_path_raw) if storage_path_raw != null else ""
	
	# Pokud cesta končí na .res/.tres, je to soubor, ale my potřebujeme SLOŽKU.
	if data_dir.ends_with(".res") or data_dir.ends_with(".tres") or data_dir.ends_with(".godot"):
		data_dir = data_dir.get_base_dir()
	
	# Pokud je cesta zadána, ujistíme se, že složka existuje
	if data_dir != "":
		var dir = DirAccess.open("res://")
		if not dir.dir_exists(data_dir):
			var err = dir.make_dir_recursive(data_dir)
			if err != OK:
				return JSON.stringify({"status": "error", "message": "Nelze vytvořit adresář pro data: " + data_dir})

	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return JSON.stringify({"status": "error", "message": "Žádná otevřená scéna"})
	
	var parent = edited_scene
	if parent_path != "":
		parent = edited_scene.get_node_or_null(parent_path)
		if not parent: return JSON.stringify({"status": "error", "message": "Parent nenalezen"})

	# 4. Instanciace hlavního uzlu
	var terrain = ClassDB.instantiate("Terrain3D")
	if not terrain: return JSON.stringify({"status": "error", "message": "Nelze instanciovat Terrain3D"})
	terrain.name = name
	
	# 5. Nastavení komponent (Assets, Data, Material) dle verze 1.0+
	
	# Assets (Textury)
	if ClassDB.class_exists("Terrain3DAssets"):
		var assets = ClassDB.instantiate("Terrain3DAssets")
		terrain.set("assets", assets)
	
	# Material (Vzhled)
	if ClassDB.class_exists("Terrain3DMaterial"):
		var material = ClassDB.instantiate("Terrain3DMaterial")
		terrain.set("material", material)

	# Data (Heightmapa) - Vytvoříme instanci Data
	if ClassDB.class_exists("Terrain3DData"):
		var data = ClassDB.instantiate("Terrain3DData")
		terrain.set("data", data)
	else:
		terrain.free()
		return JSON.stringify({"status": "error", "message": "Chybí třída Terrain3DData."})

	# 6. Nastavení adresáře (toto spustí interní logiku pluginu pro načtení/uložení)
	if data_dir != "":
		terrain.set("data_directory", data_dir)
	
	# 7. Přidání do scény
	parent.add_child(terrain)
	terrain.owner = edited_scene
	
	return JSON.stringify({"status": "ok", "message": "Terrain3D vytvořen.", "path": str(terrain.get_path()), "data_dir": data_dir})

func terrain_configure(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	if "vertex_spacing" in command: t.vertex_spacing = float(command.vertex_spacing)
	if "mesh_size" in command: t.mesh_size = int(command.mesh_size)
	if "mesh_lods" in command: t.mesh_lods = int(command.mesh_lods)
	if "cull_margin" in command: t.cull_margin = float(command.cull_margin)
	
	# Region size se mění metodou, nikoliv vlastností (dle docs)
	if "region_size" in command:
		# Ověříme, zda metoda existuje
		if t.has_method("change_region_size"):
			t.change_region_size(int(command.region_size))
		else:
			# Fallback kdyby se API změnilo zpět na property
			t.set("region_size", int(command.region_size))
		
	return JSON.stringify({"status": "ok", "message": "Konfigurace terénu aktualizována"})

func terrain_physics(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	# Mapování starého parametru 'collision_enabled' na 'collision_mode'
	# Dokumentace neříká přesně, co je který mód, ale obvykle 0 = Disabled, 1 = Enabled/Bullet
	if "collision_enabled" in command:
		var enabled = bool(command.collision_enabled)
		if enabled:
			t.set("collision_mode", 1) # Předpoklad: 1 je defaultní aktivní mód
		else:
			t.set("collision_mode", 0) # Předpoklad: 0 je disabled
			
	# Přímé nastavení vlastností (dle dokumentace jsou to aliasingy na hlavním uzlu)
	if "layer" in command: t.collision_layer = int(command.layer)
	if "mask" in command: t.collision_mask = int(command.mask)
	if "priority" in command: t.collision_priority = float(command.priority)
	if "radius" in command: t.collision_radius = int(command.radius)
	
	return JSON.stringify({"status": "ok", "message": "Fyzika terénu aktualizována"})

func set_terrain_collision(command: Dictionary) -> String:
	# Wrapper pro zpětnou kompatibilitu
	var enabled = command.get("enabled", true)
	command["collision_enabled"] = enabled
	return terrain_physics(command)
	
func terrain_import_heightmap(command: Dictionary) -> String:
	var node_path = command.get("node_path", "")
	var file_path = command.get("file_path", "")
	var min_height = float(command.get("min_height", 0.0))
	var max_height = float(command.get("max_height", 100.0))
	var position_arr = command.get("position", [0, 0, 0])
	
	# 1. Získání Node a Data
	var t = _get_terrain(node_path)
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D node nenalezen"})
	
	var data = t.get_data()
	if not data: return JSON.stringify({"status": "error", "message": "Terrain3D nemá inicializovaná Data (Terrain3DData)"})

	# 2. Načtení obrázku
	if not FileAccess.file_exists(file_path):
		return JSON.stringify({"status": "error", "message": "Soubor heightmapy neexistuje: " + file_path})
		
	var img = Image.new()
	var err = img.load(file_path)
	if err != OK:
		return JSON.stringify({"status": "error", "message": "Nelze načíst obrázek (Error code: " + str(err) + ")"})

	# 3. Výpočet scale a offset
	# Terrain3D importuje 0..1 (z obrázku) -> offset..scale
	# Rozsah: scale je rozdíl (max - min), offset je min.
	var scale = max_height - min_height
	var offset = min_height
	var pos_vec = Vector3(position_arr[0], position_arr[1], position_arr[2])

	# 4. Volání import_images
	# Signatura: import_images(images: Array[Image], global_position: Vector3, offset: float, scale: float)
	# Pole [img] obsahuje heightmapu jako první prvek.
	# Poznámka: Pokud byste importovali i control mapy, byly by další v poli.
	
	if data.has_method("import_images"):
		data.import_images([img], pos_vec, offset, scale)
		
		# Vynutit update vizuálu
		if t.has_method("update_gizmos"): t.update_gizmos()
		
		return JSON.stringify({"status": "ok", "message": "Heightmapa importována"})
	else:
		return JSON.stringify({"status": "error", "message": "Metoda 'import_images' na Terrain3DData neexistuje (špatná verze pluginu?)"})

func terrain_rendering(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	if "cast_shadows" in command: t.cast_shadows = int(command.cast_shadows)
	if "gi_mode" in command: t.gi_mode = int(command.gi_mode)
	if "render_layers" in command: t.render_layers = int(command.render_layers)
	
	return JSON.stringify({"status": "ok", "message": "Renderování terénu aktualizováno"})

func terrain_visuals(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	if "debug_level" in command: t.debug_level = int(command.debug_level)
	
	# Tyto vlastnosti jsou aliasy na Material, měly by fungovat přímo na hlavním uzlu
	if "show_grid" in command: t.set("show_region_grid", bool(command.show_grid)) # Docs říkají: show_region_grid je alias
	if "show_instances" in command: t.show_instances = bool(command.show_instances)
	if "show_heightmap" in command: t.set("show_heightmap", bool(command.show_heightmap))
	if "show_colormap" in command: t.set("show_colormap", bool(command.show_colormap))
	
	return JSON.stringify({"status": "ok", "message": "Vizuály terénu aktualizovány"})

func terrain_bake_mesh(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	var lod = int(command.get("lod", 4))
	# Volání bake_mesh(lod, filter=0)
	var mesh = t.bake_mesh(lod, 0)
	
	if not mesh:
		return JSON.stringify({"status": "error", "message": "Nepodařilo se vypect mesh"})
	
	var msg = "Mesh vypečen (Počet vertexů: %d)" % mesh.get_surface_count()
	
	# Uložení meshe
	var save_path = command.get("save_path", "")
	if save_path != "":
		var err = ResourceSaver.save(mesh, save_path)
		if err == OK:
			msg += ". Uloženo do " + save_path
		else:
			msg += ". Chyba při ukládání: " + str(err)
		
	return JSON.stringify({"status": "ok", "message": msg})

func terrain_get_height(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path", ""))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	
	var x = float(command.get("x", 0))
	var z = float(command.get("z", 0))
	
	# Vytvoříme raycasting seshora
	var src = Vector3(x, 10000.0, z)
	var dir = Vector3.DOWN
	
	# get_intersection(src, dir, gpu_mode=false)
	var hit = t.get_intersection(src, dir, false)
	
	# Kontrola "miss" hodnoty (Terrain3D vrací > 3.4e38 pro miss)
	if hit.z > 3.0e38:
		return JSON.stringify({"status": "ok", "data": "Mimo terén"})
		
	return JSON.stringify({"status": "ok", "data": {"position": [hit.x, hit.y, hit.z]}})
	
# ============================================================================
# PRÁCE S UZLY (NODE OPERATIONS)
# ============================================================================

func create_node(command: Dictionary) -> String:
	var node_type = command.get("type", "Node3D")
	var node_name = command.get("name", "NewNode")
	
	var parent_path_raw = command.get("parent")
	var parent_path: String = str(parent_path_raw) if parent_path_raw != null else ""
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: 
		return JSON.stringify({"status": "error", "message": "Žádná otevřená scéna"})
	
	var new_node = create_node_by_type(node_type)
	if not new_node: 
		return JSON.stringify({"status": "error", "message": "Neplatný typ node: " + node_type})
	
	new_node.name = node_name
	
	var parent = edited_scene
	if parent_path != "":
		parent = edited_scene.get_node_or_null(parent_path)
		if not parent:
			new_node.free()
			return JSON.stringify({"status": "error", "message": "Parent nenalezen: " + parent_path})
	
	parent.add_child(new_node)
	new_node.owner = edited_scene
	
	return JSON.stringify({"status": "ok", "message": "Node vytvořen", "path": str(new_node.get_path())})

func set_property(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var prop_name = command.get("prop", "")
	var value = command.get("val")
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	
	var node = edited_scene.get_node_or_null(node_path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	var converted_value = convert_value(value, prop_name)
	
	if prop_name in node:
		node.set(prop_name, converted_value)
		return JSON.stringify({"status": "ok", "message": "Vlastnost nastavena"})
	else:
		return JSON.stringify({"status": "error", "message": "Vlastnost neexistuje: " + prop_name})

func reparent_node(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var new_parent_path = command.get("new_parent", "")
	var keep_global = command.get("keep_global_transform", true)
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(node_path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	var new_parent = edited_scene
	if new_parent_path != "":
		new_parent = edited_scene.get_node_or_null(new_parent_path)
		if not new_parent: return JSON.stringify({"status": "error", "message": "Nový parent nenalezen"})
	
	node.reparent(new_parent, keep_global)
	node.owner = edited_scene
	
	return JSON.stringify({"status": "ok", "message": "Node přesunut"})

func duplicate_node(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var new_name = command.get("name", "")
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(node_path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	var dup = node.duplicate()
	if new_name != "": dup.name = new_name
	
	node.get_parent().add_child(dup)
	apply_owner_recursive(dup, edited_scene)
	
	return JSON.stringify({"status": "ok", "message": "Duplikováno", "path": str(dup.get_path())})

func delete_node(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(node_path)
	
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	if node == edited_scene: return JSON.stringify({"status": "error", "message": "Nelze smazat root"})
	
	node.queue_free()
	return JSON.stringify({"status": "ok", "message": "Smazáno"})

func rename_node(command: Dictionary) -> String:
	var path = command.get("path", "")
	var new_name = command.get("new_name", "")
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if node:
		node.name = new_name
		return JSON.stringify({"status": "ok", "message": "Přejmenováno"})
	return JSON.stringify({"status": "error", "message": "Node nenalezen"})

func get_node_info(command: Dictionary) -> String:
	var path = command.get("path", "")
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	var info = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"children_count": node.get_child_count(),
		"groups": node.get_groups()
	}
	
	if node is Node3D:
		info["position"] = [node.position.x, node.position.y, node.position.z]
		info["rotation_degrees"] = [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z]
	
	return JSON.stringify({"status": "ok", "info": info})

func set_owner_recursive(command: Dictionary) -> String:
	var path = command.get("path", "")
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	apply_owner_recursive(node, edited_scene)
	return JSON.stringify({"status": "ok", "message": "Owner opraven"})

# ============================================================================
# SCÉNY (SCENE OPERATIONS)
# ============================================================================

func get_scene_tree() -> String:
	var s = EditorInterface.get_edited_scene_root()
	if not s: return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	return JSON.stringify({"status": "ok", "tree": build_tree_recursive(s)})

func save_scene(command: Dictionary) -> String:
	var path = command.get("path", "")
	if path != "":
		var packed = PackedScene.new()
		packed.pack(EditorInterface.get_edited_scene_root())
		var err = ResourceSaver.save(packed, path)
		if err != OK: return JSON.stringify({"status": "error", "message": "Chyba ukládání: " + str(err)})
	else:
		EditorInterface.save_scene()
	return JSON.stringify({"status": "ok", "message": "Uloženo"})

func create_scene(command: Dictionary) -> String:
	var path = command.get("save_path", "")
	var root_type = command.get("root_type", "Node3D")
	var name = command.get("name", "SceneRoot")
	
	if path == "": return JSON.stringify({"status": "error", "message": "Chybí save_path"})
	
	var root = create_node_by_type(root_type)
	if not root: return JSON.stringify({"status": "error", "message": "Neplatný root type"})
	root.name = name
	
	var packed = PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()
	
	EditorInterface.open_scene_from_path(path)
	return JSON.stringify({"status": "ok", "message": "Scéna vytvořena"})

func load_scene(command: Dictionary) -> String:
	var path = command.get("path", "")
	if path == "": 
		return JSON.stringify({"status": "error", "message": "Chybí path"})
	
	# Kontrola existence souboru před načtením
	if not FileAccess.file_exists(path):
		return JSON.stringify({"status": "error", "message": "Soubor scény neexistuje: " + path})
	
	# V Godot 4 tato funkce nevrací hodnotu, prostě ji zavoláme
	EditorInterface.open_scene_from_path(path)
	
	return JSON.stringify({"status": "ok", "message": "Příkaz k načtení scény odeslán"})

func add_child_scene(command: Dictionary) -> String:
	var scene_path = command.get("scene_path", "")
	var parent_path = command.get("parent", "")
	var name = command.get("name", "")
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	
	if not FileAccess.file_exists(scene_path):
		return JSON.stringify({"status": "error", "message": "Soubor neexistuje"})
		
	var packed = load(scene_path)
	if not packed: return JSON.stringify({"status": "error", "message": "Nelze načíst .tscn"})
	
	var instance = packed.instantiate()
	if name != "": instance.name = name
	
	var parent = edited_scene
	if parent_path != "":
		parent = edited_scene.get_node_or_null(parent_path)
		if not parent:
			instance.free()
			return JSON.stringify({"status": "error", "message": "Parent nenalezen"})
	
	parent.add_child(instance)
	instance.owner = edited_scene
	
	return JSON.stringify({"status": "ok", "message": "Instance přidána", "path": str(instance.get_path())})

# ============================================================================
# MESH A FYZIKA (MESH & PHYSICS)
# ============================================================================

func set_mesh(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var mesh_type = command.get("mesh_type", "BoxMesh")
	var params = command.get("params", {})
	
	print("MCP DEBUG: Mesh '%s' -> '%s'" % [mesh_type, node_path])
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(node_path)
	
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	if not (node is MeshInstance3D): return JSON.stringify({"status": "error", "message": "Node není MeshInstance3D"})
	
	var mesh = create_mesh_by_type(mesh_type, params)
	if mesh:
		node.mesh = mesh
		node.notify_property_list_changed()
		node.update_gizmos()
		return JSON.stringify({"status": "ok", "message": "Mesh nastaven"})
	
	return JSON.stringify({"status": "error", "message": "Chyba vytváření meshe"})

func add_collision_shape(command: Dictionary) -> String:
	var parent_path = command.get("parent", "")
	var shape_type = command.get("shape_type", "BoxShape3D")
	var params = command.get("params", {})
	var name = command.get("name", "CollisionShape")
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var parent = edited_scene.get_node_or_null(parent_path)
	if not parent: return JSON.stringify({"status": "error", "message": "Parent nenalezen"})
	
	var node
	var shape
	
	if "3D" in shape_type:
		node = CollisionShape3D.new()
		shape = create_collision_shape_3d(shape_type, params)
	else:
		node = CollisionShape2D.new()
		shape = create_collision_shape_2d(shape_type, params)
	
	if not shape: return JSON.stringify({"status": "error", "message": "Neplatný shape"})
	
	node.name = name
	node.shape = shape
	parent.add_child(node)
	node.owner = edited_scene
	
	return JSON.stringify({"status": "ok", "message": "Shape přidán", "path": str(node.get_path())})

func get_collision_layers() -> String:
	var layers = {}
	for i in range(1, 33):
		var l3d = ProjectSettings.get_setting("layer_names/3d_physics/layer_" + str(i))
		if l3d and l3d != "": layers["3d_layer_" + str(i)] = l3d
	return JSON.stringify({"status": "ok", "layers": layers})

func _modify_collision_bitmask(command: Dictionary, prop: String) -> String:
	var path = command.get("path", "")
	var layer_idx = int(command.get("layer", 1))
	var enabled = command.get("enabled", true)
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	if prop in node:
		var current = node.get(prop)
		if enabled: node.set(prop, current | (1 << (layer_idx - 1)))
		else: node.set(prop, current & ~(1 << (layer_idx - 1)))
		return JSON.stringify({"status": "ok", "message": prop + " updated"})
	return JSON.stringify({"status": "error", "message": "Node nemá " + prop})

# ============================================================================
# SKRIPTY (SCRIPTS)
# ============================================================================

func create_script(command: Dictionary) -> String:
	var path = command.get("path", "")
	var content = command.get("content", "")
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		EditorInterface.get_resource_filesystem().scan()
		return JSON.stringify({"status": "ok", "message": "Skript vytvořen"})
	return JSON.stringify({"status": "error", "message": "Chyba zápisu"})

func save_script(command: Dictionary) -> String:
	return create_script(command)

func delete_script(command: Dictionary) -> String:
	var path = command.get("path", "")
	var dir = DirAccess.open("res://")
	if dir.remove(path) == OK:
		EditorInterface.get_resource_filesystem().scan()
		return JSON.stringify({"status": "ok", "message": "Smazáno"})
	return JSON.stringify({"status": "error", "message": "Chyba mazání"})

func attach_script(command: Dictionary) -> String:
	var path = command.get("path", "")
	var script_path = command.get("script_path", "")
	
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	
	if not FileAccess.file_exists(script_path):
		return JSON.stringify({"status": "error", "message": "Skript neexistuje"})
		
	var script = load(script_path)
	node.set_script(script)
	return JSON.stringify({"status": "ok", "message": "Skript připojen"})

func detach_script(command: Dictionary) -> String:
	var path = command.get("path", "")
	var edited_scene = EditorInterface.get_edited_scene_root()
	var node = edited_scene.get_node_or_null(path)
	if node:
		node.set_script(null)
		return JSON.stringify({"status": "ok", "message": "Odpojeno"})
	return JSON.stringify({"status": "error", "message": "Node nenalezen"})

func get_script_content(command: Dictionary) -> String:
	var path = command.get("path", "")
	if FileAccess.file_exists(path):
		var file = FileAccess.open(path, FileAccess.READ)
		var content = file.get_as_text()
		return JSON.stringify({"status": "ok", "content": content})
	return JSON.stringify({"status": "error", "message": "Soubor neexistuje"})

# ============================================================================
# POMOCNÉ FUNKCE (HELPERS)
# ============================================================================

func build_tree_recursive(node: Node) -> Dictionary:
	var tree = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"children": []
	}
	for child in node.get_children():
		tree["children"].append(build_tree_recursive(child))
	return tree

func create_node_by_type(type: String) -> Node:
	if ClassDB.can_instantiate(type):
		return ClassDB.instantiate(type)
	return null

func convert_value(value, prop_name: String):
	if typeof(value) == TYPE_ARRAY:
		if value.size() == 3: return Vector3(value[0], value[1], value[2])
		if value.size() == 2: return Vector2(value[0], value[1])
	return value

func apply_owner_recursive(node: Node, owner_node: Node):
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		apply_owner_recursive(child, owner_node)

func create_mesh_by_type(type: String, params: Dictionary) -> Mesh:
	var mesh
	# Ošetření vstupu
	type = type.strip_edges()
	match type:
		"BoxMesh": 
			mesh = BoxMesh.new()
			if params.has("size"): mesh.size = _vec3(params.size)
		"SphereMesh": 
			mesh = SphereMesh.new()
			if params.has("radius"): mesh.radius = float(params.radius)
			if params.has("height"): mesh.height = float(params.height)
		"CapsuleMesh": 
			mesh = CapsuleMesh.new()
			if params.has("radius"): mesh.radius = float(params.radius)
			if params.has("height"): mesh.height = float(params.height)
		"CylinderMesh": 
			mesh = CylinderMesh.new()
			if params.has("top_radius"): mesh.top_radius = float(params.top_radius)
			if params.has("bottom_radius"): mesh.bottom_radius = float(params.bottom_radius)
			if params.has("height"): mesh.height = float(params.height)
		"PlaneMesh": 
			mesh = PlaneMesh.new()
			if params.has("size"): mesh.size = _vec2(params.size)
		"PrismMesh": 
			mesh = PrismMesh.new()
			if params.has("size"): mesh.size = _vec3(params.size)
		"TorusMesh": 
			mesh = TorusMesh.new()
			if params.has("inner_radius"): mesh.inner_radius = float(params.inner_radius)
			if params.has("outer_radius"): mesh.outer_radius = float(params.outer_radius)
	return mesh

func create_collision_shape_3d(type: String, params: Dictionary) -> Shape3D:
	var shape
	match type:
		"BoxShape3D": 
			shape = BoxShape3D.new()
			if params.has("size"): shape.size = _vec3(params.size)
		"SphereShape3D": 
			shape = SphereShape3D.new()
			if params.has("radius"): shape.radius = float(params.radius)
		"CapsuleShape3D": 
			shape = CapsuleShape3D.new()
			if params.has("radius"): shape.radius = float(params.radius)
			if params.has("height"): shape.height = float(params.height)
		"CylinderShape3D": 
			shape = CylinderShape3D.new()
			if params.has("radius"): shape.radius = float(params.radius)
			if params.has("height"): shape.height = float(params.height)
		"WorldBoundaryShape3D": 
			shape = WorldBoundaryShape3D.new()
	return shape

func create_collision_shape_2d(type: String, params: Dictionary) -> Shape2D:
	var shape
	match type:
		"RectangleShape2D": 
			shape = RectangleShape2D.new()
			if params.has("size"): shape.size = _vec2(params.size)
		"CircleShape2D": 
			shape = CircleShape2D.new()
			if params.has("radius"): shape.radius = float(params.radius)
		"CapsuleShape2D": 
			shape = CapsuleShape2D.new()
	return shape

func _vec3(arr) -> Vector3:
	if typeof(arr) != TYPE_ARRAY or arr.size() < 3: return Vector3(1, 1, 1)
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))

func _vec2(arr) -> Vector2:
	if typeof(arr) != TYPE_ARRAY or arr.size() < 2: return Vector2(1, 1)
	return Vector2(float(arr[0]), float(arr[1]))

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		if server:
			server.stop()
		print("✓ TCP Server zastaven")
