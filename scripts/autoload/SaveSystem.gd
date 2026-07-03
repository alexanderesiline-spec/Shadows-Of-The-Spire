extends Node

# JSON to user:// for debuggability. Serializes what actually needs to
# survive a reload: world_seed (the biome grid regenerates identically from
# it — never stored itself), ChunkDeltaStore's sparse terrain edits, player
# state, NPC drifted state keyed by npc_name (stable — see the relationships
# key migration in NPC.gd), and player-placed buildings. The hand-authored
# town Point of Interest itself is NOT saved — it's immutable and recreated
# identically every boot from WorldMap.gd's own spawn logic.
#
# Note: there's no "continue game" entry point yet (RacePicker always runs
# first), so a full PlayerStats object isn't reconstructed on load — only the
# fields that matter to resume mid-session (position, mana, inventory) are
# restored. Wiring a real continue-flow is a natural follow-up once this is
# played through an actual Godot editor.

const SAVE_PATH := "user://save_slot_1.json"

const PlaceScript = preload("res://scripts/world/Place.gd")
const PlaceScene = preload("res://scenes/Place.tscn")
const ChunkDeltaStoreScript = preload("res://scripts/world/chunk/ChunkDeltaStore.gd")

func save_game() -> void:
	var data := {
		"world_seed": BiomeMap.world_seed,
		"chunk_deltas": ChunkDeltaStoreScript.serialize(),
		"player": _serialize_player(),
		"npcs": _serialize_npcs(),
		"placed_buildings": _serialize_placed_buildings(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		EventBus.log_warning("Could not save — file access failed.")
		return
	file.store_string(JSON.stringify(data))
	file.close()
	EventBus.log_info("Game saved.")

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		EventBus.log_warning("No save file found.")
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		EventBus.log_warning("Save file is corrupt.")
		return false
	_apply(parsed)
	EventBus.log_info("Game loaded.")
	return true

# ── Serialize ────────────────────────────────────────────────────────────────

func _serialize_player() -> Dictionary:
	var player := _get_player()
	if player == null:
		return {}
	var inv: Dictionary = player.build_mode.inventory.counts if player.build_mode else {}
	return {
		"race_name": player.race_name,
		"world_tile_pos": [player.world_tile_pos.x, player.world_tile_pos.y],
		"mana": player.mana,
		"max_mana": player.max_mana,
		"inventory": inv,
	}

func _serialize_npcs() -> Dictionary:
	var out := {}
	for n in WorldSimulation.npcs:
		if is_instance_valid(n):
			out[n.npc_name] = n.serialize_state()
	return out

func _serialize_placed_buildings() -> Array:
	var out: Array = []
	for p in WorldSimulation.places:
		if is_instance_valid(p) and p.place_type in PlaceScript.BUILDABLE_TYPES:
			out.append({
				"place_name": p.place_name,
				"place_type": p.place_type,
				"position": [p.position.x, p.position.y],
			})
	return out

# ── Apply ────────────────────────────────────────────────────────────────────

func _apply(data: Dictionary) -> void:
	if data.has("world_seed"):
		BiomeMap.world_seed = int(data["world_seed"])
		BiomeMap.rebuild()
	if data.has("chunk_deltas"):
		ChunkDeltaStoreScript.deserialize(data["chunk_deltas"])
	if data.has("npcs"):
		var npc_states: Dictionary = data["npcs"]
		for npc_name in npc_states:
			var n := _find_npc(npc_name)
			if n != null:
				n.apply_state(npc_states[npc_name])
	if data.has("player"):
		_apply_player(data["player"])
	if data.has("placed_buildings"):
		_restore_placed_buildings(data["placed_buildings"])

func _apply_player(pdata: Dictionary) -> void:
	var player := _get_player()
	if player == null:
		return
	if pdata.has("world_tile_pos"):
		var pos: Array = pdata["world_tile_pos"]
		player.world_tile_pos = Vector2(pos[0], pos[1])
	player.mana = pdata.get("mana", player.mana)
	player.max_mana = pdata.get("max_mana", player.max_mana)
	if pdata.has("inventory") and player.build_mode:
		player.build_mode.inventory.counts = pdata["inventory"]

func _restore_placed_buildings(list: Array) -> void:
	var poi := _get_town_poi()
	if poi == null:
		return
	for entry in list:
		var p: Node = PlaceScene.instantiate()
		p.place_name = entry["place_name"]
		p.place_type = int(entry["place_type"])
		var pos: Array = entry["position"]
		p.position = Vector2(pos[0], pos[1])
		poi.add_child(p)

# ── Lookups ──────────────────────────────────────────────────────────────────

func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _find_npc(npc_name: String) -> Node:
	for n in WorldSimulation.npcs:
		if is_instance_valid(n) and n.npc_name == npc_name:
			return n
	return null

func _get_town_poi() -> Node:
	for poi in WorldSimulation.pois:
		if is_instance_valid(poi):
			return poi
	return null
