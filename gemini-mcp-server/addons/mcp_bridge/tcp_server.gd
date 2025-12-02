extends Node

const PORT = 4242
var server: TCPServer
var clients: Array = []
var _process_enabled: bool = true

var ops_2d = preload("res://addons/mcp_bridge/ops_2d.gd").new()

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
				_handle_client_data(client, data)
		
		i += 1

# Pomocná asynchronní funkce pro zpracování požadavku
func _handle_client_data(client: StreamPeerTCP, data: String):
	var response = await process_command(data)
	if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		client.put_data(response.to_utf8_buffer())

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
		"get_prop": return get_property(command)
		"call_method": return call_method(command)
		"connect_signal": return connect_signal(command)
		"create_node_2d": return await ops_2d.create_node_2d(command)
		"set_transform_2d": return ops_2d.set_transform_2d(command)
		"get_info_2d": return ops_2d.get_info_2d(command)
		"ui_set_layout": return ops_2d.ui_set_layout(command)
		# --- ENV ---
		"env_create": return env_create()
		"env_set_background": return env_set_background(command)
		"env_set_effect": return env_set_effect(command)
		"env_set_camera_attributes": return env_set_camera_attributes(command)
		# --- FILESYSTEM ---
		"search_files": return search_files(command)
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
		"terrain_add_texture": return terrain_add_texture(command)
		"terrain_add_mesh": return terrain_add_mesh(command)
		"terrain_place_instances": return terrain_place_instances(command)
		"terrain_bake_navmesh": return terrain_bake_navmesh(command)
		"terrain_raycast": return terrain_raycast(command)
		"terrain_task": return terrain_task(command)
		
		# --- UZLY (bude v další části) ---
		"create_node": return await create_node(command)
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
		"load_scene": return await load_scene(command)
		"add_child_scene": return add_child_scene(command)
		
		# --- MESH A FYZIKA (bude v další části) ---
		"set_mesh": return set_mesh(command)
		"add_collision_shape": return add_collision_shape(command)
		"get_collision_layers": return get_collision_layers(command) # POZOR: nyní bere command
		"set_collision_layer_name": return set_collision_layer_name(command)
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

func search_files(command: Dictionary) -> String:
	var query = command.get("query", "").to_lower()
	var extensions = command.get("extensions", []) # Volitelné filtrování přípon
	var root = command.get("root", "res://")
	
	var results = []
	_search_recursive(root, query, extensions, results)
	
	# Omezíme výsledky, aby se nezahltil kontext (max 50 nálezů)
	if results.size() > 50:
		var total = results.size()
		results = results.slice(0, 50)
		return JSON.stringify({"status": "ok", "files": results, "message": "Nalezeno %d souborů (zobrazeno prvních 50). Upřesni dotaz." % total})
		
	return JSON.stringify({"status": "ok", "files": results})

func _search_recursive(path: String, query: String, extensions: Array, results: Array):
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = path.path_join(file_name)
				
				if dir.current_is_dir():
					# Pokud složka obsahuje query, přidáme ji taky
					if query == "" or query in file_name.to_lower():
						pass # Složky zatím nepřidáváme do výsledků, jen rekurzivně prohledáváme
					_search_recursive(full_path, query, extensions, results)
				else:
					# Kontrola souboru
					var match_query = (query == "" or query in file_name.to_lower())
					var match_ext = (extensions.is_empty() or ("." + file_name.get_extension()) in extensions)
					
					if match_query and match_ext:
						results.append(full_path)
						
			file_name = dir.get_next()

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
	var scale = max_height - min_height
	var offset = min_height
	var pos_vec = Vector3(position_arr[0], position_arr[1], position_arr[2])

	# 4. Volání import_images - OPRAVA PRO VERZI 1.0+
	# Musíme předat pole [Height, Control, Color]. Použijeme null pro mapy, které nemáme.
	if data.has_method("import_images"):
		var images_array = [img, null, null]
		data.import_images(images_array, pos_vec, offset, scale)
		# Vynutit update vizuálu a kolizí
		if t.has_method("update_gizmos"): t.update_gizmos()
		if t.has_method("update_collision"): t.update_collision()
		return JSON.stringify({"status": "ok", "message": "Heightmapa importována (Height scale: " + str(scale) + ")"})
	else:
		return JSON.stringify({"status": "error", "message": "Metoda 'import_images' na Terrain3DData neexistuje."})

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
	var parent_path = str(command.get("parent", ""))
	var edited_scene = EditorInterface.get_edited_scene_root()
	if not edited_scene: return JSON.stringify({"status": "error", "message": "Žádná scéna"})
	var new_node = create_node_by_type(node_type)
	if not new_node: return JSON.stringify({"status": "error", "message": "Neplatný typ"})
	new_node.name = node_name
	var parent = edited_scene
	if parent_path != "":
		parent = edited_scene.get_node_or_null(parent_path)
		if not parent:
			new_node.free()
			return JSON.stringify({"status": "error", "message": "Parent nenalezen"})
	parent.add_child(new_node)
	new_node.owner = edited_scene
	await get_tree().process_frame
	if is_instance_valid(new_node):
		return JSON.stringify({"status": "ok", "message": "Node vytvořen", "path": str(new_node.get_path())})
	else:
		return JSON.stringify({"status": "error", "message": "Node byl vytvořen, ale ihned zmizel (chyba enginu?)"})

func set_property(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var prop_name = command.get("prop", "")
	var value = command.get("val")
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(node_path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	var converted_value = convert_value(value, prop_name)
	node.set_indexed(prop_name, converted_value)
	return JSON.stringify({"status": "ok", "message": "Vlastnost " + prop_name + " nastavena"})

func get_property(command: Dictionary) -> String:
	var node_path = command.get("path", "")
	var prop_name = command.get("prop", "")
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(node_path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	var val = node.get_indexed(prop_name)
	if val is Vector2: val = [val.x, val.y]
	elif val is Vector3: val = [val.x, val.y, val.z]
	elif val is Color: val = [val.r, val.g, val.b, val.a]
	elif val is Object: val = str(val)
	return JSON.stringify({"status": "ok", "value": val})

func call_method(command: Dictionary) -> String:
	var path = command.get("path", "")
	var method = command.get("method", "")
	var args = command.get("args", [])
	var node = EditorInterface.get_edited_scene_root().get_node_or_null(path)
	if not node: return JSON.stringify({"status": "error", "message": "Node nenalezen"})
	if not node.has_method(method):
		return JSON.stringify({"status": "error", "message": "Metoda " + method + " neexistuje"})
	var clean_args = []
	for arg in args:
		if typeof(arg) == TYPE_ARRAY and arg.size() == 3:
			clean_args.append(Vector3(arg[0], arg[1], arg[2]))
		else:
			clean_args.append(arg)
	var result = node.callv(method, clean_args)
	var str_res = str(result) if result != null else "void"
	return JSON.stringify({"status": "ok", "result": str_res})

func connect_signal(command: Dictionary) -> String:
	var src_path = command.get("source_path", "")
	var sig_name = command.get("signal_name", "")
	var tgt_path = command.get("target_path", "")
	var method = command.get("method_name", "")
	var root = EditorInterface.get_edited_scene_root()
	var src = root.get_node_or_null(src_path)
	var tgt = root.get_node_or_null(tgt_path)
	if not src or not tgt: return JSON.stringify({"status": "error", "message": "Uzly nenalezeny"})
	if not src.has_signal(sig_name):
		return JSON.stringify({"status": "error", "message": "Signál " + sig_name + " neexistuje"})
	if src.is_connected(sig_name, Callable(tgt, method)):
		return JSON.stringify({"status": "ok", "message": "Již propojeno"})
	src.connect(sig_name, Callable(tgt, method))
	return JSON.stringify({"status": "ok", "message": "Signál propojen"})

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
	var requested_path = command.get("path", "")
	
	if requested_path == "":
		EditorInterface.save_scene()
		return JSON.stringify({"status": "ok", "message": "Aktuální scéna uložena"})
		
	var final_path = _get_unique_path(requested_path)
	
	var packed = PackedScene.new()
	var result = packed.pack(EditorInterface.get_edited_scene_root())
	
	if result == OK:
		var err = ResourceSaver.save(packed, final_path)
		if err == OK:
			return JSON.stringify({"status": "ok", "message": "Uloženo jako: " + final_path, "path": final_path})
		return JSON.stringify({"status": "error", "message": "Chyba ResourceSaver: " + str(err)})
		
	return JSON.stringify({"status": "error", "message": "Chyba při packování scény"})

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
	if not FileAccess.file_exists(path):
		return JSON.stringify({"status": "error", "message": "Soubor neexistuje"})
	EditorInterface.open_scene_from_path(path)
	var max_retries = 20
	while max_retries > 0:
		await get_tree().process_frame
		var current_root = EditorInterface.get_edited_scene_root()
		if current_root and current_root.scene_file_path == path:
			break
		max_retries -= 1
	return JSON.stringify({"status": "ok", "message": "Scéna načtena a připravena"})

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

func get_collision_layers(command: Dictionary) -> String:
	var type = command.get("type", "3D")
	var prefix = "layer_names/3d_physics/layer_"
	if type == "2D":
		prefix = "layer_names/2d_physics/layer_"
	var layers = {}
	for i in range(1, 33):
		var setting_path = prefix + str(i)
		if ProjectSettings.has_setting(setting_path):
			var name = ProjectSettings.get_setting(setting_path)
			if str(name) != "":
				layers[str(i)] = name
	return JSON.stringify({
		"status": "ok",
		"type": type,
		"layers": layers,
		"message": "Nalezeno %d pojmenovaných vrstev." % layers.size()
	})

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
	var requested_path = command.get("path", "")
	var content = command.get("content", "")
	var overwrite = command.get("overwrite", false) # Možnost vynutit přepsání
	
	var final_path = requested_path
	if not overwrite:
		final_path = _get_unique_path(requested_path)
	
	var file = FileAccess.open(final_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		EditorInterface.get_resource_filesystem().scan()
		
		var msg = "Skript vytvořen"
		if final_path != requested_path:
			msg = "Soubor existoval. Vytvořen nový název: " + final_path
			
		return JSON.stringify({"status": "ok", "message": msg, "path": final_path})
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

func _get_unique_path(path: String) -> String:
	# Pokud soubor neexistuje, cesta je bezpečná
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return path
	
	var base_dir = path.get_base_dir()
	var filename = path.get_file()
	var extension = filename.get_extension()
	var basename = filename.get_basename()
	
	var counter = 1
	var new_path = path
	
	# Cyklus dokud nenajdeme volné jméno
	while FileAccess.file_exists(new_path) or DirAccess.dir_exists_absolute(new_path):
		var new_filename = basename + "_" + str(counter)
		if extension != "":
			new_filename += "." + extension
		new_path = base_dir.path_join(new_filename)
		counter += 1
		
	return new_path

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

func _get_world_env() -> WorldEnvironment:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return null
	for child in root.get_children():
		if child is WorldEnvironment:
			return child
	var we = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	root.add_child(we)
	we.owner = root
	return we

func env_create() -> String:
	var we = _get_world_env()
	if not we:
		return JSON.stringify({"status": "error", "message": "Nelze vytvořit WorldEnvironment"})
	if not we.environment:
		we.environment = Environment.new()
	if not we.camera_attributes:
		we.camera_attributes = CameraAttributesPractical.new()
	return JSON.stringify({"status": "ok", "message": "WorldEnvironment inicializován", "path": str(we.get_path())})

func env_set_background(command: Dictionary) -> String:
	var we = _get_world_env()
	if not we or not we.environment:
		return JSON.stringify({"status": "error", "message": "Chybí Environment"})
	var env = we.environment
	var mode = command.get("mode", "clear_color")
	var energy = float(command.get("energy", 1.0))
	var col_arr = command.get("color", [0, 0, 0])
	var color = _arr_to_col(col_arr)
	match mode:
		"clear_color":
			env.background_mode = Environment.BG_CLEAR_COLOR
		"custom_color":
			env.background_mode = Environment.BG_COLOR
			env.background_color = color
		"sky":
			env.background_mode = Environment.BG_SKY
			if not env.sky:
				var sky = Sky.new()
				sky.sky_material = ProceduralSkyMaterial.new()
				env.sky = sky
		"canvas":
			env.background_mode = Environment.BG_CANVAS
		_:
			pass
	env.background_energy_multiplier = energy
	return JSON.stringify({"status": "ok", "message": "Pozadí nastaveno"})

func env_set_effect(command: Dictionary) -> String:
	var we = _get_world_env()
	if not we or not we.environment:
		return JSON.stringify({"status": "error", "message": "Chybí Environment (spusť godot_env_create)"})
	var env = we.environment
	var type = command.get("type", "")
	var enabled = bool(command.get("enabled", true))
	var p = command.get("params", {})
	match type:
		"tonemap":
			if "mode" in p:
				env.tonemap_mode = int(p.mode)
			if "exposure" in p:
				env.tonemap_exposure = float(p.exposure)
			if "white" in p:
				env.tonemap_white = float(p.white)
		"glow":
			env.glow_enabled = enabled
			if "intensity" in p:
				env.glow_intensity = float(p.intensity)
			if "strength" in p:
				env.glow_strength = float(p.strength)
			if "bloom" in p:
				env.glow_bloom = float(p.bloom)
			if "blend_mode" in p:
				env.glow_blend_mode = int(p.blend_mode)
			if "hdr_threshold" in p:
				env.glow_hdr_threshold = float(p.hdr_threshold)
		"fog":
			env.fog_enabled = enabled
			if "density" in p:
				env.fog_density = float(p.density)
			if "light_color" in p:
				env.fog_light_color = _arr_to_col(p.light_color)
			if "sun_scatter" in p:
				env.fog_sun_scatter = float(p.sun_scatter)
			if "height_density" in p:
				env.fog_height_density = float(p.height_density)
		"volumetric_fog":
			env.volumetric_fog_enabled = enabled
			if "density" in p:
				env.volumetric_fog_density = float(p.density)
			if "albedo" in p:
				env.volumetric_fog_albedo = _arr_to_col(p.albedo)
			if "emission" in p:
				env.volumetric_fog_emission = _arr_to_col(p.emission)
			if "length" in p:
				env.volumetric_fog_length = float(p.length)
			if "detail_spread" in p:
				env.volumetric_fog_detail_spread = float(p.detail_spread)
		"ssao":
			env.ssao_enabled = enabled
			if "radius" in p:
				env.ssao_radius = float(p.radius)
			if "intensity" in p:
				env.ssao_intensity = float(p.intensity)
			if "power" in p:
				env.ssao_power = float(p.power)
			if "detail" in p:
				env.ssao_detail = float(p.detail)
			if "horizon" in p:
				env.ssao_horizon = float(p.horizon)
		"ssil":
			env.ssil_enabled = enabled
			if "radius" in p:
				env.ssil_radius = float(p.radius)
			if "intensity" in p:
				env.ssil_intensity = float(p.intensity)
		"sdfgi":
			env.sdfgi_enabled = enabled
			if "use_occlusion" in p:
				env.sdfgi_use_occlusion = bool(p.use_occlusion)
			if "bounce_feedback" in p:
				env.sdfgi_bounce_feedback = float(p.bounce_feedback)
			if "cascades" in p:
				env.sdfgi_cascades = int(p.cascades)
			if "min_cell_size" in p:
				env.sdfgi_min_cell_size = float(p.min_cell_size)
		"adjustment":
			env.adjustment_enabled = enabled
			if "brightness" in p:
				env.adjustment_brightness = float(p.brightness)
			if "contrast" in p:
				env.adjustment_contrast = float(p.contrast)
			if "saturation" in p:
				env.adjustment_saturation = float(p.saturation)
		_:
			return JSON.stringify({"status": "error", "message": "Neznámý efekt: " + type})
	return JSON.stringify({"status": "ok", "message": "Efekt " + type + " aktualizován"})

func env_set_camera_attributes(command: Dictionary) -> String:
	var we = _get_world_env()
	if not we:
		return JSON.stringify({"status": "error", "message": "WorldEnvironment nenalezen"})
	if not we.camera_attributes or not (we.camera_attributes is CameraAttributesPractical):
		we.camera_attributes = CameraAttributesPractical.new()
	var cam = we.camera_attributes
	if "auto_exposure" in command:
		cam.auto_exposure_enabled = bool(command.auto_exposure)
	if "exposure_multiplier" in command:
		cam.exposure_multiplier = float(command.exposure_multiplier)
	if "exposure_sensitivity" in command:
		cam.exposure_sensitivity = float(command.exposure_sensitivity)
	if "auto_exposure_speed" in command:
		cam.auto_exposure_speed = float(command.auto_exposure_speed)
	if "auto_exposure_scale" in command:
		cam.auto_exposure_scale = float(command.auto_exposure_scale)
	return JSON.stringify({"status": "ok", "message": "CameraAttributes nastaveny"})

func _arr_to_col(arr) -> Color:
	if typeof(arr) == TYPE_ARRAY and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(1, 1, 1)

# ============================================================================
# TERRAIN 3D ADVANCED IO (Importer/Exporter)
# ============================================================================

func terrain_task(command: Dictionary) -> String:
	var importer_scene_path = "res://addons/terrain_3d/tools/importer.tscn"
	if not FileAccess.file_exists(importer_scene_path):
		return JSON.stringify({"status": "error", "message": "Terrain3D Importer nenalezen (zkontrolujte instalaci pluginu)."})
	var importer_scene = load(importer_scene_path)
	var importer = importer_scene.instantiate()
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		importer.free()
		return JSON.stringify({"status": "error", "message": "Žádná otevřená scéna"})
	root.add_child(importer)
	var task_type = command.get("task_type")
	var map_type = command.get("map_type")
	var file_path = command.get("file_path", "")
	var data_dir = command.get("data_dir", "")
	var p = command.get("params", {})
	var temp_terrain = ClassDB.instantiate("Terrain3D")
	if ClassDB.class_exists("Terrain3DData"):
		var data = ClassDB.instantiate("Terrain3DData")
		temp_terrain.set("data", data)
		temp_terrain.set("data_directory", data_dir)
	importer.set("terrain_node", temp_terrain)
	var result_msg = ""
	var success = false
	if task_type == "import":
		if map_type == "height":
			importer.set("height_file_name", file_path)
		elif map_type == "control":
			importer.set("control_file_name", file_path)
		elif map_type == "color":
			importer.set("color_file_name", file_path)
		if "position" in p:
			var pos = p.position
			importer.set("import_position", Vector3(pos[0], pos[1], pos[2]))
		if "scale" in p:
			importer.set("import_scale", float(p.scale))
		if "offset" in p:
			importer.set("height_offset", float(p.offset))
		if "min_height" in p:
			importer.set("r16_range_min", float(p.min_height))
		if "max_height" in p:
			importer.set("r16_range_max", float(p.max_height))
		if "r16_dim" in p:
			var dim = p.r16_dim
			importer.set("r16_size", Vector2i(dim[0], dim[1]))
		if importer.has_method("run_import"):
			importer.run_import()
			result_msg = "Import spuštěn (Heightmap/Color/Control)"
			success = true
		else:
			result_msg = "Importer nemá metodu run_import()"
	elif task_type == "export":
		if map_type == "height":
			importer.set("export_type", 0)
		elif map_type == "color":
			importer.set("export_type", 1)
		elif map_type == "control":
			importer.set("export_type", 2)
		importer.set("export_file_name", file_path)
		if importer.has_method("run_export"):
			importer.run_export()
			result_msg = "Export spuštěn do " + file_path
			success = true
		else:
			result_msg = "Importer nemá metodu run_export()"
	root.remove_child(importer)
	importer.queue_free()
	temp_terrain.free()
	if success:
		EditorInterface.get_resource_filesystem().scan()
		return JSON.stringify({"status": "ok", "message": result_msg})
	else:
		return JSON.stringify({"status": "error", "message": result_msg})

# ============================================================================
# TERRAIN 3D ADVANCED (Assets, Foliage, Nav)
# ============================================================================

func terrain_add_texture(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path"))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	var assets = t.get_assets()
	if not assets: return JSON.stringify({"status": "error", "message": "Chybí Assets"})
	var albedo_path = command.get("albedo_path", "")
	var normal_path = command.get("normal_path", "")
	if not FileAccess.file_exists(albedo_path):
		return JSON.stringify({"status": "error", "message": "Albedo textura neexistuje"})
	var tex_asset = ClassDB.instantiate("Terrain3DTextureAsset")
	tex_asset.name = command.get("name", "NewTexture")
	tex_asset.albedo = load(albedo_path)
	if normal_path != "" and FileAccess.file_exists(normal_path):
		tex_asset.normal = load(normal_path)
	tex_asset.uv_scale = float(command.get("uv_scale", 1.0))
	assets.add_texture(tex_asset)
	var new_id = assets.get_texture_count() - 1
	return JSON.stringify({"status": "ok", "message": "Textura přidána", "id": new_id})

func terrain_add_mesh(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path"))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	var assets = t.get_assets()
	if not assets: return JSON.stringify({"status": "error", "message": "Chybí Assets"})
	var mesh_path = command.get("mesh_path", "")
	if not FileAccess.file_exists(mesh_path):
		return JSON.stringify({"status": "error", "message": "Mesh soubor neexistuje"})
	var mesh_res = load(mesh_path)
	if not mesh_res: return JSON.stringify({"status": "error", "message": "Chyba načítání meshe"})
	var mesh_asset = ClassDB.instantiate("Terrain3DMeshAsset")
	mesh_asset.name = command.get("name", "Foliage")
	if mesh_res is PackedScene:
		mesh_asset.packed_scene = mesh_res
	elif mesh_res is Mesh:
		return JSON.stringify({"status": "error", "message": "Prosím použij .tscn nebo .glb soubor (PackedScene)."})
	mesh_asset.height_offset = 0.0
	mesh_asset.density = 10.0
	assets.add_mesh(mesh_asset)
	var new_id = assets.get_mesh_count() - 1
	return JSON.stringify({"status": "ok", "message": "Mesh asset registrován", "id": new_id})

func terrain_place_instances(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path"))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	var instancer = t.get_instancer()
	if not instancer: return JSON.stringify({"status": "error", "message": "Chybí Instancer"})
	var mesh_id = int(command.get("mesh_id", 0))
	var positions = command.get("positions", [])
	var auto_height = bool(command.get("auto_height", true))
	var transforms = []
	for pos_arr in positions:
		var x = float(pos_arr[0])
		var y = float(pos_arr[1])
		var z = float(pos_arr[2])
		if auto_height:
			var hit = t.get_intersection(Vector3(x, 10000, z), Vector3.DOWN, false)
			if hit.z < 3.0e38:
				y = hit.y
		var trans = Transform3D()
		trans.origin = Vector3(x, y, z)
		transforms.append(trans)
	if instancer.has_method("add_multimesh"):
		instancer.add_multimesh(mesh_id, transforms, [])
		return JSON.stringify({"status": "ok", "message": "Přidáno %d instancí" % transforms.size()})
	else:
		return JSON.stringify({"status": "error", "message": "Instancer nemá metodu add_multimesh (nekompatibilní verze?)"})

func terrain_bake_navmesh(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path"))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	var nav_region = null
	for child in t.get_children():
		if child is NavigationRegion3D:
			nav_region = child
			break
	if not nav_region:
		nav_region = NavigationRegion3D.new()
		nav_region.name = "NavigationRegion3D"
		t.add_child(nav_region)
		nav_region.owner = EditorInterface.get_edited_scene_root()
		nav_region.navigation_mesh = NavigationMesh.new()
		nav_region.navigation_mesh.agent_max_climb = 1.0
		nav_region.navigation_mesh.agent_max_slope = 45.0
	NavigationMeshGenerator.bake(nav_region.navigation_mesh, nav_region)
	return JSON.stringify({"status": "ok", "message": "NavMesh bake spuštěn."})

func terrain_raycast(command: Dictionary) -> String:
	var t = _get_terrain(command.get("node_path"))
	if not t: return JSON.stringify({"status": "error", "message": "Terrain3D nenalezen"})
	var x = float(command.get("x", 0))
	var z = float(command.get("z", 0))
	var hit = t.get_intersection(Vector3(x, 10000, z), Vector3.DOWN, false)
	if hit.z > 3.0e38:
		return JSON.stringify({"status": "ok", "hit": false, "y": 0.0})
	return JSON.stringify({"status": "ok", "hit": true, "position": [hit.x, hit.y, hit.z], "y": hit.y})

# ============================================================================
# PROJECT SETTINGS (PHYSICS LAYERS)
# ============================================================================

func set_collision_layer_name(command: Dictionary) -> String:
	var idx = int(command.get("index", 0))
	var new_name = command.get("name", "")
	var type = command.get("type", "3D")
	if idx < 1 or idx > 32:
		return JSON.stringify({"status": "error", "message": "Index vrstvy musí být 1-32."})
	var setting_path = "layer_names/3d_physics/layer_" + str(idx)
	if type == "2D":
		setting_path = "layer_names/2d_physics/layer_" + str(idx)
	ProjectSettings.set_setting(setting_path, new_name)
	var err = ProjectSettings.save()
	if err != OK:
		return JSON.stringify({"status": "error", "message": "Nepodařilo se uložit ProjectSettings. Error: " + str(err)})
	var action = "Přejmenována"
	if new_name == "":
		action = "Smazána/Resetována"
	return JSON.stringify({
		"status": "ok",
		"message": "%s vrstva %d (%s) -> '%s'" % [action, idx, type, new_name]
	})
