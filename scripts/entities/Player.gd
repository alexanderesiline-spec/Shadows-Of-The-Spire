extends CharacterBody2D

# A free-roaming observer/participant. The world runs with or without them, but
# the player can now nudge it: greeting builds trust, threatening breaks it.
# Faction alignment and real combat/economy come in a later phase.
#
# Movement model (floating origin): the player's node itself stays pinned at a
# fixed local anchor (position never changes) — WorldRoot recomputes every
# chunk/POI's screen position each frame relative to `world_tile_pos` instead.
# So "moving" here means advancing the canonical world_tile_pos coordinate,
# wrapped into the finite world range, not moving this node via physics.
# See scripts/world/WorldRoot.gd for why this keeps all of NPC.gd's existing
# distance-based logic correct with zero changes.

const TileConfig = preload("res://scripts/world/tile/TileConfig.gd")
const RaceData = preload("res://scripts/entities/RaceData.gd")
const BuildModeScript = preload("res://scripts/world/BuildMode.gd")

const SPEED: float = 170.0   # pixels/sec, same feel as before — see _physics_process
const INTERACT_RADIUS: float = 90.0
const TRUST_SEED_RADIUS: float = 500.0   # "crossed paths" range, not just interact range

# Canonical world position in whole tile units — the single source of truth
# for "where the player actually is" in the large wraparound world.
var world_tile_pos: Vector2 = Vector2(1000.0, 1000.0)

# Race/stats, read once from CharacterSetup at boot. `species` mirrors NPC.gd's
# convention exactly so SpeciesLore/relationship code treats the player like
# any other species for seeding purposes. `race_trust_mod` is read by
# NPC.seed_trust_for_player via a generic "does this thing have this
# property" check, so NPC.gd never needs to know Player.gd's type.
var race_name: String = "Human"
var species: String = "human"
var race_trust_mod: float = 0.0
var stats: RefCounted = null   # a PlayerStats instance
const GREET_TRUST_GAIN: float = 1.0
const GREET_COOLDOWN_HOURS: int = 3       # stops trust-farming by spamming E
const THREATEN_TRUST_LOSS: float = 25.0
const THREATEN_FEAR_GAIN: float = 35.0
const THREATEN_GOSSIP_RADIUS: float = 220.0

# Mana — the resource, not spells yet. Untrained average mage: 100 pool (lore).
var mana: float = 100.0
var max_mana: float = 100.0
const MANA_RESTORE_RESTING: float = 100.0 / 2.5   # full in ~2.5h stationary
const MANA_RESTORE_WALKING: float = 100.0 / 4.5   # full in ~4.5h while moving

var _nearby_npc: Node = null
var _moved_this_hour: bool = false
var _greet_cooldowns: Dictionary = {}   # NPC instance id -> hours remaining
var _sprite: AnimatedSprite2D = null    # only set if the real sheet exists
var facing: Vector2 = Vector2.DOWN      # last nonzero move direction — read by BuildMode
var build_mode: RefCounted = null       # a BuildMode instance

func _ready() -> void:
	add_to_group("player")
	_apply_character_setup()
	_build_visual()
	build_mode = BuildModeScript.new(self)
	GameClock.hour_passed.connect(_on_hour_passed)

func _apply_character_setup() -> void:
	race_name = CharacterSetup.chosen_race
	species = RaceData.species_string(race_name)
	race_trust_mod = RaceData.trust_mod(race_name)
	stats = CharacterSetup.get_stats()
	max_mana = 100.0 * stats.mana_multiplier()
	mana = max_mana
	if RaceData.has_spawn_override(race_name):
		world_tile_pos = RaceData.spawn_tile_pos(race_name)

func _build_visual() -> void:
	if not _try_build_sprite():
		_build_polygon_fallback()

	var camera := Camera2D.new()
	camera.zoom = Vector2(1.5, 1.5)
	add_child(camera)

func _build_polygon_fallback() -> void:
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-7, 10), Vector2(7, 10),
		Vector2(9, -2), Vector2(4, -6),
		Vector2(4, -14), Vector2(-4, -14),
		Vector2(-4, -6), Vector2(-9, -2)
	])
	body.color = Color(0.2, 0.55, 1.0)
	add_child(body)

	var head := Polygon2D.new()
	head.polygon = PackedVector2Array([
		Vector2(-5, -14), Vector2(5, -14),
		Vector2(5, -22), Vector2(-5, -22)
	])
	head.color = Color(0.9, 0.75, 0.6)
	add_child(head)

# Data-driven, degrades gracefully: builds an AnimatedSprite2D from the real
# walk-cycle sheet if it exists at the expected path; returns false (falling
# back to the Polygon2D shapes above, unchanged) if it doesn't. Auto-upgrades
# the moment the file is dropped in — no code change needed either way.
#
# Assumed sheet layout (unconfirmed — artist hasn't provided the file yet):
# one image, 4 rows (down/left/right/up, top to bottom) x 8 columns. Frame
# size is derived from the actual image dimensions, not hardcoded, so any
# resolution works as long as the 4x8 grid holds.
func _try_build_sprite() -> bool:
	if not ResourceLoader.exists(TileConfig.PLAYER_WALK_SHEET_PATH):
		return false

	var sheet: Texture2D = load(TileConfig.PLAYER_WALK_SHEET_PATH)
	var frame_w := sheet.get_width() / 8
	var frame_h := sheet.get_height() / 4
	var row_names := ["walk_down", "walk_left", "walk_right", "walk_up"]

	var frames := SpriteFrames.new()
	for row in range(row_names.size()):
		var anim_name: String = row_names[row]
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, 8.0)
		for col in range(8):
			var region := Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = region
			frames.add_frame(anim_name, atlas)

	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.animation = "walk_down"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	return true

func _update_facing_animation(dir: Vector2) -> void:
	if _sprite == null:
		return
	if dir == Vector2.ZERO:
		_sprite.stop()
		return
	var anim: String
	if absf(dir.x) > absf(dir.y):
		anim = "walk_right" if dir.x > 0.0 else "walk_left"
	else:
		anim = "walk_down" if dir.y > 0.0 else "walk_up"
	if _sprite.animation != anim:
		_sprite.animation = anim
	if not _sprite.is_playing():
		_sprite.play()

func _physics_process(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if dir != Vector2.ZERO:
		velocity = dir.normalized() * SPEED   # kept for future sprite-facing use
		facing = dir.normalized()
		var speed_mult := stats.speed_multiplier() if stats else 1.0
		var tiles_per_sec := (SPEED * speed_mult) / float(TileConfig.LOGICAL_TILE_SIZE.x)
		world_tile_pos += dir.normalized() * tiles_per_sec * delta
		_wrap_world_tile_pos()
		_moved_this_hour = true
	else:
		velocity = velocity.move_toward(Vector2.ZERO, SPEED * 8.0)
	_update_facing_animation(dir)
	_update_nearby()

func _wrap_world_tile_pos() -> void:
	var world_w := float(TileConfig.WORLD_CHUNKS_X * TileConfig.CHUNK_SIZE_TILES)
	var world_h := float(TileConfig.WORLD_CHUNKS_Y * TileConfig.CHUNK_SIZE_TILES)
	world_tile_pos.x = fposmod(world_tile_pos.x, world_w)
	world_tile_pos.y = fposmod(world_tile_pos.y, world_h)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode"):
		build_mode.toggle()
	elif build_mode.is_active():
		# While building, Greet/Threaten's keys do double duty as Place/Cycle
		# instead — building has the player's full attention either way.
		if event.is_action_pressed("interact"):
			build_mode.try_place()
		elif event.is_action_pressed("threaten"):
			build_mode.cycle_type()
	elif event.is_action_pressed("interact") and _nearby_npc != null:
		_greet()
	elif event.is_action_pressed("threaten") and _nearby_npc != null:
		_threaten()

func _update_nearby() -> void:
	_nearby_npc = null
	var best_dist := INTERACT_RADIUS
	for n in WorldSimulation.npcs:
		if is_instance_valid(n):
			var d: float = global_position.distance_to(n.global_position)
			if d <= TRUST_SEED_RADIUS:
				n.seed_trust_for_player(self)
			if d < best_dist:
				best_dist = d
				_nearby_npc = n

func get_nearby_npc() -> Node:
	return _nearby_npc

# ── Mana restoration ─────────────────────────────────────────────────────────
# Ticks once per in-game hour (mirrors how NPC needs regen) rather than per
# frame, keyed on whether the player stood still or walked during that hour.
# Lore's "no restoration in combat/running" tier has no hook yet — there's no
# combat or sprint in this build — so only the two active tiers apply so far.

func _on_hour_passed(_hour: int) -> void:
	var rate := MANA_RESTORE_WALKING if _moved_this_hour else MANA_RESTORE_RESTING
	mana = clampf(mana + rate, 0.0, max_mana)
	_moved_this_hour = false
	_tick_greet_cooldowns()

func get_mana_status() -> String:
	return "Mana %d / %d" % [int(mana), int(max_mana)]

# ── Greet & Threaten — the player's two levers on NPC trust ─────────────────

func _greet() -> void:
	var n := _nearby_npc
	EventBus.player_interacted.emit(n.npc_name, n.get_detail())
	EventBus.log_info("[You inspect] %s" % n.get_status_short())

	var response: String = n.trade_response()
	if response != "":
		EventBus.log_info(response)

	var id := n.get_instance_id()
	if not _greet_cooldowns.has(id):
		n.adjust_trust(GREET_TRUST_GAIN)
		_greet_cooldowns[id] = GREET_COOLDOWN_HOURS

func _threaten() -> void:
	var n := _nearby_npc
	n.adjust_trust(-THREATEN_TRUST_LOSS)
	n.fear = clampf(n.fear + THREATEN_FEAR_GAIN, 0.0, 100.0)
	EventBus.notable(n.npc_name, "You threaten %s. They recoil in fear." % n.npc_name, 2)
	WorldSimulation.gossip_near(n.global_position, -8.0, THREATEN_GOSSIP_RADIUS, n, n)

func _tick_greet_cooldowns() -> void:
	var expired: Array = []
	for id in _greet_cooldowns:
		_greet_cooldowns[id] -= 1
		if _greet_cooldowns[id] <= 0:
			expired.append(id)
	for id in expired:
		_greet_cooldowns.erase(id)

# ── Inspection (HUD) ─────────────────────────────────────────────────────────

func get_status() -> String:
	var s := "%s   %s" % [race_name, get_mana_status()]
	if build_mode != null and build_mode.is_active():
		var label: String = build_mode.PlaceScript.TYPE_LABELS[build_mode.selected_type]
		s += "\n[BUILD MODE] %s — [E] place  [R] cycle  [B] exit" % label
	elif _nearby_npc and is_instance_valid(_nearby_npc):
		s += "\nNear: %s\n[E] greet   [R] threaten   [B] build" % _nearby_npc.get_status_short()
	else:
		s += "\nWandering the plains town...\nWalk up to someone and press E."
	return s
