extends StaticBody3D

signal interacted(part: Node3D, player: Node3D)

@export var part_id: StringName

func _ready() -> void:
	add_to_group("mustang_parts")
	
	# --- TATO ČÁST BYLA PŘIDÁNA ---
	# Počkáme, až bude celý strom scény připraven, abychom měli jistotu, že všechny uzly existují.
	await get_tree().process_frame
	
	# Najdeme hlavní uzel vozidla (který je ve skupině "vehicle")
	var vehicle_nodes = get_tree().get_nodes_in_group("vehicle")
	if not vehicle_nodes.is_empty():
		var vehicle = vehicle_nodes[0] # Předpokládáme, že je ve scéně jen jedno vozidlo
		# Připojíme náš signál "interacted" na funkci "_on_part_interacted" ve vozidle
		if vehicle.has_method("_on_part_interacted"):
			interacted.connect(vehicle._on_part_interacted)
			print("[Interaction] Část '", part_id, "' se úspěšně připojila k vozidlu '", vehicle.name, "'.")
		else:
			printerr("[Interaction] Část '", part_id, "' nenašla na vozidle metodu '_on_part_interacted'!")
	else:
		printerr("[Interaction] Část '", part_id, "' nenašla ve scéně žádný uzel ve skupině 'vehicle'!")
	# -----------------------------

	print("[Interaction] Připraveno pro část: ", part_id)

func interact(player_node: Node3D) -> void:
	print("[Interaction] Interakce spuštěna na části: ", part_id)
	emit_signal("interacted", self, player_node)
