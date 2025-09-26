extends Node3D

var grid_snap_size = 1
@export var domino_prefab: PackedScene
var domino_material = preload("res://Extras/domino_mesh.tres")
@export var grid_size: float = grid_snap_size
@export var domino_spacing: float = grid_snap_size  # space between dominoes
@export var line_count: int = 10  # number of dominoes to place in a line
@export var line_rotation: float = 0.0  # rotation of the domino line in degrees
@export var topple_force: float = 1.0  # force applied to topple dominoes

enum PlacementMode { SINGLE, LINE, CURVE, SPIRAL }
@export var placement_mode: PlacementMode = PlacementMode.SINGLE

@export var curve_radius: float = 7
@export var curve_angle_deg: float = 180.0
@export var curve_direction: int = 1  # 1 for clockwise, -1 for counterclockwise
@export var curve_domino_count: int = 24
@export var curve_full_rotation: float = 0.0  # Rotation of the entire curve in degrees

@export var spiral_turns: float = 3.0  # Number of complete 360-degree turns
@export var spiral_radius_start: float = 2.0  # Starting radius of spiral
@export var spiral_radius_end: float = 8.0  # Ending radius of spiral
@export var spiral_domino_count: int = 60  # Number of dominoes in spiral

var preview_domino: Node3D = null
var preview_dominoes: Array[Node3D] = []
var play_mode: bool = false  # toggle between placement and play mode
var placed_dominoes: Array[RigidBody3D] = []  # keep track of placed dominoes

@onready var world_env = $WorldEnvironment

# Save file path and version
const SAVE_FILE_PATH = "user://domino_save.json"
const SAVE_VERSION = "1.1.0"  # Updated version for level name support

# Color picker references
@onready var background_color_picker = $UILayer/UI/ParamsPanel/VBox/BackgroundColorPicker
@onready var ground_color_picker = $UILayer/UI/ParamsPanel/VBox/GroundColor
@onready var domino_color_picker = $UILayer/UI/ParamsPanel/VBox/DominoColor

# Level name reference
@onready var level_name_input = $UILayer/UI/ParamsPanel/VBox/LevelName

# Default colors and level name
var default_background_color = Color(0.0, 1.0, 1.0)  # Dark gray
var default_ground_color = Color(0.0, 1.0, 0.0)     # Greenish
var default_domino_color = Color(1.0, 1.0, 1.0)     # Light gray/white
var default_level_name = "Untitled Level"

# Current level name
var current_level_name: String = default_level_name

func _ready() -> void:
	create_preview_domino()
	# Initialize level name input
	if level_name_input:
		level_name_input.text = current_level_name

func _process(_delta: float) -> void:
	if not play_mode:
		update_preview()
	
	if Input.is_action_just_pressed("mb_left"):
		if play_mode:
			topple_domino_at_mouse()
		else:
			place_domino_at_mouse()

func is_mouse_over_ui() -> bool:
	# Check if mouse is over any node in the "UI" group
	var mouse_pos = get_viewport().get_mouse_position()
	var ui_nodes = get_tree().get_nodes_in_group("UI")
	for ui_node in ui_nodes:
		if ui_node is Control:
			var rect = ui_node.get_global_rect()
			if rect.has_point(mouse_pos):
				return true
	return false

func place_domino_at_mouse() -> void:
	# Skip placement if mouse is over UI
	if is_mouse_over_ui():
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var base_pos = result.position
		base_pos.x = round(base_pos.x / grid_size) * grid_size
		base_pos.z = round(base_pos.z / grid_size) * grid_size
		base_pos.y = result.position.y + 1.0  # Place above the hit surface
		
		match placement_mode:
			PlacementMode.SINGLE:
				place_domino(base_pos)
			PlacementMode.LINE:
				place_line(base_pos)
			PlacementMode.CURVE:
				place_curve(base_pos)
			PlacementMode.SPIRAL:
				place_spiral(base_pos)

func topple_domino_at_mouse() -> void:
	# Allow toppling even over UI, as it's a different interaction
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider is RigidBody3D:
		var domino = result.collider as RigidBody3D
		# Check if this is one of our placed dominoes
		if domino in placed_dominoes:
			topple_domino(domino)

func topple_domino(domino: RigidBody3D) -> void:
	# Unfreeze the domino if it was frozen
	domino.freeze = false
	
	# Get mouse position in world space
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Create a plane at the domino's height to find where the mouse is pointing
	var plane = Plane(Vector3.UP, domino.global_position.y)
	var intersection = plane.intersects_ray(from, to - from)
	
	if intersection:
		# Calculate direction from domino center to mouse intersection point
		var to_mouse_direction = (intersection - domino.global_position).normalized()
		
		# Get the domino's forward direction (X-axis)
		var domino_forward = domino.global_transform.basis.x
		
		# Determine if we need to flip the direction based on mouse position
		var dot_product = to_mouse_direction.dot(domino_forward)
		
		# Always apply force in the domino's forward direction (X-axis)
		var tip_force = domino_forward * topple_force
		
		# If mouse is behind the domino, flip the force direction
		if dot_product < 0:
			tip_force = -tip_force
		
		# Apply force above center to create tipping motion
		var force_offset = Vector3(0, 0.5, 0)  # Apply force above center
		domino.apply_force(tip_force, force_offset)
		
		print("Toppled domino forward along X-axis at: ", domino.global_position)

func create_preview_domino() -> void:
	if domino_prefab:
		preview_domino = domino_prefab.instantiate()
		add_child(preview_domino)
		make_transparent(preview_domino)
		preview_domino.visible = false

func make_transparent(node: Node) -> void:
	# Only process Node3D nodes and skip other types like Timer, AudioStreamPlayer, etc.
	if not node is Node3D:
		return
	
	# Make all MeshInstance3D nodes transparent with bright colors
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance = child as MeshInstance3D
			# Always create a new bright material for maximum visibility
			var material = StandardMaterial3D.new()
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color = Color(1.0, 0.3, 0.0, 0.8)  # Bright orange with 80% opacity
			material.emission_enabled = true
			material.emission = Color(1.0, 0.5, 0.0)  # Bright orange glow
			material.emission_energy = 2.0  # Make it really glow
			material.flags_unshaded = true  # Ignore lighting for consistent visibility
			material.no_depth_test = true  # Always render on top
			mesh_instance.material_override = material
		
		# Recursively apply to children (but only Node3D children)
		if child is Node3D:
			make_transparent(child)
	
	# Disable physics for preview - only for Node3D nodes
	var node3d = node as Node3D
	if node3d.has_method("set_freeze_mode"):
		node3d.set_freeze_mode(RigidBody3D.FREEZE_MODE_KINEMATIC)
	if node3d is RigidBody3D:
		var rigid_body = node3d as RigidBody3D
		rigid_body.freeze = true
		rigid_body.set_collision_layer_value(1, false)  # Disable collision layer
		rigid_body.set_collision_mask_value(1, false)   # Disable collision mask

func update_preview() -> void:
	# Skip preview update if mouse is over UI
	if is_mouse_over_ui():
		if preview_domino:
			preview_domino.visible = false
		clear_preview_dominoes()
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	var camera = get_viewport().get_camera_3d()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	# Clear previous preview dominoes for line/curve/spiral modes
	clear_preview_dominoes()
	
	if result:
		var base_pos = result.position
		base_pos.x = round(base_pos.x / grid_size) * grid_size
		base_pos.z = round(base_pos.z / grid_size) * grid_size
		base_pos.y = result.position.y + 1.0  # Place above the hit surface
		
		match placement_mode:
			PlacementMode.SINGLE:
				if preview_domino:
					preview_domino.global_position = base_pos
					preview_domino.visible = true
			PlacementMode.LINE:
				create_line_preview(base_pos)
			PlacementMode.CURVE:
				create_curve_preview(base_pos)
			PlacementMode.SPIRAL:
				create_spiral_preview(base_pos)
	else:
		if preview_domino:
			preview_domino.visible = false

func create_line_preview(start_pos: Vector3) -> void:
	var rotation_rad = deg_to_rad(line_rotation)
	var direction = Vector3(cos(rotation_rad), 0, sin(rotation_rad))  # Rotated direction
	
	for i in range(line_count):
		var preview = domino_prefab.instantiate()
		add_child(preview)
		make_transparent(preview)
		preview_dominoes.append(preview)
		
		var offset = direction * domino_spacing * i
		var pos = start_pos + offset
		# Snap to grid after applying rotation offset
		pos.x = round(pos.x / grid_size) * grid_size
		pos.z = round(pos.z / grid_size) * grid_size
		pos.y = start_pos.y  # Use the same Y as start position
		
		preview.global_position = pos
		# Rotate each domino to align with the line direction
		preview.global_rotation = Vector3(0, rotation_rad, 0)

func create_curve_preview(center_pos: Vector3) -> void:
	var arc_angle = deg_to_rad(curve_angle_deg)
	var arc_length = arc_angle * curve_radius
	var actual_domino_count = max(2, int(arc_length / domino_spacing) + 1)
	var angle_step = arc_angle / float(actual_domino_count - 1)
	var radius = curve_radius
	var start_angle = -arc_angle / 2.0
	var full_rotation_rad = deg_to_rad(curve_full_rotation)

	for i in range(actual_domino_count):
		var angle = start_angle + (angle_step * i * curve_direction)
		# Apply full rotation to the curve
		var rotated_angle = angle + full_rotation_rad
		var pos_x = radius * cos(rotated_angle)
		var pos_z = radius * sin(rotated_angle)
		var pos = center_pos + Vector3(pos_x, 0, pos_z)
		var tangent_angle = rotated_angle + (PI / 2.0)
		var rotation_y = -tangent_angle
		var preview = domino_prefab.instantiate()
		add_child(preview)
		make_transparent(preview)
		preview_dominoes.append(preview)
		preview.global_position = pos
		preview.global_rotation = Vector3(0, rotation_y, 0)

func create_spiral_preview(center_pos: Vector3) -> void:
	var total_angle = deg_to_rad(360.0 * spiral_turns)
	var segments = 1000
	var total_arc_length = 0.0
	
	for i in range(segments):
		var t1 = float(i) / float(segments)
		var t2 = float(i + 1) / float(segments)
		var angle1 = total_angle * t1
		var angle2 = total_angle * t2
		var radius1 = lerp(spiral_radius_start, spiral_radius_end, t1)
		var radius2 = lerp(spiral_radius_start, spiral_radius_end, t2)
		var x1 = radius1 * cos(angle1)
		var z1 = radius1 * sin(angle1)
		var x2 = radius2 * cos(angle2)
		var z2 = radius2 * sin(angle2)
		var segment_length = sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1))
		total_arc_length += segment_length
	
	var actual_domino_count = max(2, int(total_arc_length / domino_spacing) + 1)
	var target_spacing = total_arc_length / float(actual_domino_count - 1)
	var current_arc_length = 0.0
	var domino_index = 0
	
	for i in range(segments):
		if domino_index >= actual_domino_count:
			break
		var t1 = float(i) / float(segments)
		var t2 = float(i + 1) / float(segments)
		var angle1 = total_angle * t1 * curve_direction
		var angle2 = total_angle * t2 * curve_direction
		var radius1 = lerp(spiral_radius_start, spiral_radius_end, t1)
		var radius2 = lerp(spiral_radius_start, spiral_radius_end, t2)
		var x1 = radius1 * cos(angle1)
		var z1 = radius1 * sin(angle1)
		var x2 = radius2 * cos(angle2)
		var z2 = radius2 * sin(angle2)
		var segment_length = sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1))
		var target_distance = target_spacing * domino_index
		if current_arc_length <= target_distance and current_arc_length + segment_length >= target_distance:
			var segment_progress = (target_distance - current_arc_length) / segment_length if segment_length > 0 else 0.0
			var t = lerp(t1, t2, segment_progress)
			var angle = total_angle * t * curve_direction
			var radius = lerp(spiral_radius_start, spiral_radius_end, t)
			var pos_x = radius * cos(angle)
			var pos_z = radius * sin(angle)
			var pos = center_pos + Vector3(pos_x, 0, pos_z)
			var tangent_angle = angle + (PI / 2.0)
			var rotation_y = -tangent_angle
			var preview = domino_prefab.instantiate()
			add_child(preview)
			make_transparent(preview)
			preview_dominoes.append(preview)
			preview.global_position = pos
			preview.global_rotation = Vector3(0, rotation_y, 0)
			domino_index += 1
		current_arc_length += segment_length

func clear_preview_dominoes() -> void:
	for preview in preview_dominoes:
		if is_instance_valid(preview):
			preview.queue_free()
	preview_dominoes.clear()

func place_domino(pos: Vector3) -> void:
	var domino = domino_prefab.instantiate()
	add_child(domino)
	domino.global_position = pos
	if domino is RigidBody3D:
		placed_dominoes.append(domino as RigidBody3D)

func place_line(start_pos: Vector3) -> void:
	var rotation_rad = deg_to_rad(line_rotation)
	var direction = Vector3(cos(rotation_rad), 0, sin(rotation_rad))  # Rotated direction
	
	for i in range(line_count):
		var offset = direction * domino_spacing * i
		var pos = start_pos + offset
		# Snap to grid after applying rotation offset
		pos.x = round(pos.x / grid_size) * grid_size
		pos.z = round(pos.z / grid_size) * grid_size
		pos.y = start_pos.y
		
		var domino = domino_prefab.instantiate()
		add_child(domino)
		domino.global_position = pos
		# Rotate each domino to align with the line direction
		domino.global_rotation = Vector3(0, rotation_rad, 0)
		
		if domino is RigidBody3D:
			placed_dominoes.append(domino as RigidBody3D)

func place_curve(center_pos: Vector3) -> void:
	var arc_angle = deg_to_rad(curve_angle_deg)
	var arc_length = arc_angle * curve_radius
	var actual_domino_count = max(2, int(arc_length / domino_spacing) + 1)
	var angle_step = arc_angle / float(actual_domino_count - 1)
	var radius = curve_radius
	var start_angle = -arc_angle / 2.0
	var full_rotation_rad = deg_to_rad(curve_full_rotation)

	for i in range(actual_domino_count):
		var angle = start_angle + (angle_step * i * curve_direction)
		# Apply full rotation to the curve
		var rotated_angle = angle + full_rotation_rad
		var pos_x = radius * cos(rotated_angle)
		var pos_z = radius * sin(rotated_angle)
		var pos = center_pos + Vector3(pos_x, 0, pos_z)
		var tangent_angle = rotated_angle + (PI / 2.0)
		var rotation_y = -tangent_angle
		var domino = domino_prefab.instantiate()
		add_child(domino)
		domino.global_position = pos
		domino.global_rotation = Vector3(0, rotation_y, 0)
		if domino is RigidBody3D:
			placed_dominoes.append(domino as RigidBody3D)

func place_spiral(center_pos: Vector3) -> void:
	var total_angle = deg_to_rad(360.0 * spiral_turns)
	var segments = 1000
	var total_arc_length = 0.0
	
	for i in range(segments):
		var t1 = float(i) / float(segments)
		var t2 = float(i + 1) / float(segments)
		var angle1 = total_angle * t1
		var angle2 = total_angle * t2
		var radius1 = lerp(spiral_radius_start, spiral_radius_end, t1)
		var radius2 = lerp(spiral_radius_start, spiral_radius_end, t2)
		var x1 = radius1 * cos(angle1)
		var z1 = radius1 * sin(angle1)
		var x2 = radius2 * cos(angle2)
		var z2 = radius2 * sin(angle2)
		var segment_length = sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1))
		total_arc_length += segment_length
	
	var actual_domino_count = max(2, int(total_arc_length / domino_spacing) + 1)
	var target_spacing = total_arc_length / float(actual_domino_count - 1)
	var current_arc_length = 0.0
	var domino_index = 0
	
	for i in range(segments):
		if domino_index >= actual_domino_count:
			break
		var t1 = float(i) / float(segments)
		var t2 = float(i + 1) / float(segments)
		var angle1 = total_angle * t1 * curve_direction
		var angle2 = total_angle * t2 * curve_direction
		var radius1 = lerp(spiral_radius_start, spiral_radius_end, t1)
		var radius2 = lerp(spiral_radius_start, spiral_radius_end, t2)
		var x1 = radius1 * cos(angle1)
		var z1 = radius1 * sin(angle1)
		var x2 = radius2 * cos(angle2)
		var z2 = radius2 * sin(angle2)
		var segment_length = sqrt((x2 - x1) * (x2 - x1) + (z2 - z1) * (z2 - z1))
		var target_distance = target_spacing * domino_index
		if current_arc_length <= target_distance and current_arc_length + segment_length >= target_distance:
			var segment_progress = (target_distance - current_arc_length) / segment_length if segment_length > 0 else 0.0
			var t = lerp(t1, t2, segment_progress)
			var angle = total_angle * t * curve_direction
			var radius = lerp(spiral_radius_start, spiral_radius_end, t)
			var pos_x = radius * cos(angle)
			var pos_z = radius * sin(angle)
			var pos = center_pos + Vector3(pos_x, 0, pos_z)
			var tangent_angle = angle + (PI / 2.0)
			var rotation_y = -tangent_angle
			var domino = domino_prefab.instantiate()
			add_child(domino)
			domino.global_position = pos
			domino.global_rotation = Vector3(0, rotation_y, 0)
			if domino is RigidBody3D:
				placed_dominoes.append(domino as RigidBody3D)
			domino_index += 1
		current_arc_length += segment_length

# Button functions for placement modes
func button_single() -> void:
	placement_mode = PlacementMode.SINGLE
	print("Mode: SINGLE")

func button_line() -> void:
	placement_mode = PlacementMode.LINE
	print("Mode: LINE")

func button_curve() -> void:
	placement_mode = PlacementMode.CURVE
	print("Mode: CURVE")

func button_spiral() -> void:
	placement_mode = PlacementMode.SPIRAL
	print("Mode: SPIRAL")

func button_play() -> void:
	play_mode = true
	if preview_domino:
		preview_domino.visible = false
	clear_preview_dominoes()
	$UILayer/UI/ParamsPanel.position.x = -288
	$UILayer/UI/ParamsPanel/ParamsFlyOut.text = ">"
	$UILayer/UI/BrowserPanel.position.x = 1280
	$UILayer/UI/BrowserPanel/BrowserFlyOut.text = "<"
	print("Mode: PLAY - Click dominoes to topple them!")

func button_reset() -> void:
	for domino in placed_dominoes:
		if is_instance_valid(domino):
			domino.queue_free()
	placed_dominoes.clear()
	play_mode = false
	print("All dominoes cleared - Back to BUILD mode")

# Save and Load functions with version support and level name
func save_dominoes() -> void:
	# Check if we're in play mode - if so, prevent saving
	if play_mode:
		print("Cannot save while in play mode! Switch to edit mode first.")
		return
	
	# Get current level name from input field
	if level_name_input:
		current_level_name = level_name_input.text.strip_edges()
		if current_level_name.is_empty():
			current_level_name = default_level_name
	
	var save_data = {
		"version": SAVE_VERSION,
		"level_name": current_level_name,  # New field for level name
		"dominoes": [],
		"background_color": world_env.environment.background_color.to_html(),
		"ground_color": "",
		"domino_color": domino_material.albedo_color.to_html(),
		"created_date": Time.get_datetime_string_from_system(),  # Optional: track creation date
		"domino_count": 0  # Optional: track number of dominoes
	}
	
	# Safely get ground color
	var mesh_instance = $Ground/MeshInstance3D
	if mesh_instance and mesh_instance.material_override:
		save_data["ground_color"] = mesh_instance.material_override.albedo_color.to_html()
	else:
		save_data["ground_color"] = default_ground_color.to_html()
	
	for domino in placed_dominoes:
		if is_instance_valid(domino):
			var domino_data = {
				"position": {
					"x": domino.global_position.x,
					"y": domino.global_position.y,
					"z": domino.global_position.z
				},
				"rotation": {
					"x": domino.global_rotation.x,
					"y": domino.global_rotation.y,
					"z": domino.global_rotation.z
				}
			}
			save_data["dominoes"].append(domino_data)
	
	# Update domino count
	save_data["domino_count"] = save_data["dominoes"].size()
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		print("Saved level '", current_level_name, "' with ", save_data["domino_count"], " dominoes to ", SAVE_FILE_PATH, " (version ", SAVE_VERSION, ")")
	else:
		push_error("Failed to save dominoes: ", FileAccess.get_open_error())

func load_dominoes() -> void:
	# Clear existing dominoes first
	button_reset()
	
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		
		if parse_result == OK:
			var save_data = json.get_data()
			
			# Check version for backwards compatibility
			var file_version = "1.0.0"  # Default version for old files
			if save_data.has("version"):
				file_version = save_data["version"]
				print("Loading save file version: ", file_version)
			else:
				print("Loading legacy save file (no version field)")
			
			# Handle different versions here
			match file_version:
				"1.0.0":
					load_version_1_0_0(save_data)
				"1.1.0":
					load_version_1_1_0(save_data)
				_:
					# Handle unknown versions - try to load as current version
					print("Unknown save file version: ", file_version, " - attempting to load as current version")
					load_version_1_1_0(save_data)
		else:
			push_error("Failed to parse JSON: ", json.get_error_message())
	else:
		push_error("No save file found: ", SAVE_FILE_PATH)

func load_version_1_0_0(save_data: Dictionary) -> void:
	# Load colors (same as before)
	if save_data.has("background_color"):
		var bg_color = Color(save_data["background_color"])
		world_env.environment.background_color = bg_color
		background_color_picker.color = bg_color
	
	if save_data.has("ground_color"):
		var ground_color = Color(save_data["ground_color"])
		var mesh_instance = $Ground/MeshInstance3D
		if mesh_instance:
			var material = StandardMaterial3D.new()
			material.albedo_color = ground_color
			mesh_instance.material_override = material
			ground_color_picker.color = ground_color
	
	if save_data.has("domino_color"):
		var domino_color = Color(save_data["domino_color"])
		domino_material.albedo_color = domino_color
		domino_color_picker.color = domino_color
	
	# Set level name to default for version 1.0.0 files (no level name support)
	current_level_name = default_level_name
	if level_name_input:
		level_name_input.text = current_level_name
	
	# Load dominoes
	if save_data.has("dominoes"):
		for domino_data in save_data["dominoes"]:
			var dom_position = Vector3(
				domino_data["position"]["x"],
				domino_data["position"]["y"],
				domino_data["position"]["z"]
			)
			var dom_rotation = Vector3(
				domino_data["rotation"]["x"],
				domino_data["rotation"]["y"],
				domino_data["rotation"]["z"]
			)
			
			var domino = domino_prefab.instantiate()
			add_child(domino)
			domino.global_position = dom_position
			domino.global_rotation = dom_rotation
			
			if domino is RigidBody3D:
				placed_dominoes.append(domino as RigidBody3D)
		
		print("Loaded ", save_data["dominoes"].size(), " dominoes from ", SAVE_FILE_PATH)

func load_version_1_1_0(save_data: Dictionary) -> void:
	# Load colors (same as version 1.0.0)
	if save_data.has("background_color"):
		var bg_color = Color(save_data["background_color"])
		world_env.environment.background_color = bg_color
		background_color_picker.color = bg_color
	
	if save_data.has("ground_color"):
		var ground_color = Color(save_data["ground_color"])
		var mesh_instance = $Ground/MeshInstance3D
		if mesh_instance:
			var material = StandardMaterial3D.new()
			material.albedo_color = ground_color
			mesh_instance.material_override = material
			ground_color_picker.color = ground_color
	
	if save_data.has("domino_color"):
		var domino_color = Color(save_data["domino_color"])
		domino_material.albedo_color = domino_color
		domino_color_picker.color = domino_color
	
	# Load level name (new in version 1.1.0)
	if save_data.has("level_name"):
		current_level_name = save_data["level_name"]
		# Load the actual level name back into the input field
		if level_name_input:
			level_name_input.text = current_level_name
			level_name_input.placeholder_text = default_level_name
	else:
		current_level_name = default_level_name
		if level_name_input:
			level_name_input.text = ""  # Keep empty to show placeholder
			level_name_input.placeholder_text = default_level_name
	
	# Load dominoes
	if save_data.has("dominoes"):
		for domino_data in save_data["dominoes"]:
			var dom_position = Vector3(
				domino_data["position"]["x"],
				domino_data["position"]["y"],
				domino_data["position"]["z"]
			)
			var dom_rotation = Vector3(
				domino_data["rotation"]["x"],
				domino_data["rotation"]["y"],
				domino_data["rotation"]["z"]
			)
			
			var domino = domino_prefab.instantiate()
			add_child(domino)
			domino.global_position = dom_position
			domino.global_rotation = dom_rotation
			
			if domino is RigidBody3D:
				placed_dominoes.append(domino as RigidBody3D)
		
		var domino_count = save_data.get("domino_count", save_data["dominoes"].size())
		var created_date = save_data.get("created_date", "Unknown")
		print("Loaded level '", current_level_name, "' with ", domino_count, " dominoes (created: ", created_date, ")")

# New function to create a new scene
func button_new() -> void:
	# Clear all dominoes
	button_reset()
	
	# Reset to default colors
	world_env.environment.background_color = default_background_color
	background_color_picker.color = default_background_color
	
	var mesh_instance = $Ground/MeshInstance3D
	if mesh_instance:
		var material = StandardMaterial3D.new()
		material.albedo_color = default_ground_color
		mesh_instance.material_override = material
		ground_color_picker.color = default_ground_color
	
	domino_material.albedo_color = default_domino_color
	domino_color_picker.color = default_domino_color
	
	# Reset level name
	current_level_name = default_level_name
	if level_name_input:
		level_name_input.text = current_level_name
	
	print("Created new scene with default settings")

# New function for export button
func button_export() -> void:
	# Check if we're in play mode - if so, prevent exporting
	if play_mode:
		print("Cannot export while in play mode! Switch to edit mode first.")
		return
	
	# Get current level name from input field
	if level_name_input:
		current_level_name = level_name_input.text.strip_edges()
		if current_level_name.is_empty():
			current_level_name = default_level_name
	
	var save_data = {
		"version": SAVE_VERSION,
		"level_name": current_level_name,
		"dominoes": [],
		"background_color": world_env.environment.background_color.to_html(),
		"ground_color": "",
		"domino_color": domino_material.albedo_color.to_html(),
		"created_date": Time.get_datetime_string_from_system(),
		"domino_count": 0
	}
	
	# Safely get ground color
	var mesh_instance = $Ground/MeshInstance3D
	if mesh_instance and mesh_instance.material_override:
		save_data["ground_color"] = mesh_instance.material_override.albedo_color.to_html()
	else:
		save_data["ground_color"] = default_ground_color.to_html()
	
	for domino in placed_dominoes:
		if is_instance_valid(domino):
			var domino_data = {
				"position": {
					"x": domino.global_position.x,
					"y": domino.global_position.y,
					"z": domino.global_position.z
				},
				"rotation": {
					"x": domino.global_rotation.x,
					"y": domino.global_rotation.y,
					"z": domino.global_rotation.z
				}
			}
			save_data["dominoes"].append(domino_data)
	
	# Update domino count
	save_data["domino_count"] = save_data["dominoes"].size()
	
	# Convert to JSON string
	var json_string = JSON.stringify(save_data, "\t")
	
	# Copy to clipboard
	DisplayServer.clipboard_set(json_string)
	
	print("Exported level '", current_level_name, "' with ", save_data["domino_count"], " dominoes - JSON copied to clipboard!")

# New function for import button
func button_import() -> void:
	# Get JSON string from clipboard
	var json_string = DisplayServer.clipboard_get()
	
	if json_string.is_empty():
		print("No JSON data in clipboard to import!")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result == OK:
		var import_data = json.get_data()
		
		# Switch to play mode after import
		play_mode = true
		if preview_domino:
			preview_domino.visible = false
		clear_preview_dominoes()
		$UILayer/UI/ParamsPanel.position.x = -288
		$UILayer/UI/ParamsPanel/ParamsFlyOut.text = ">"
		$UILayer/UI/BrowserPanel.position.x = 1280
		$UILayer/UI/BrowserPanel/BrowserFlyOut.text = "<"
		
		# Clear existing dominoes first
		for domino in placed_dominoes:
			if is_instance_valid(domino):
				domino.queue_free()
		placed_dominoes.clear()
		
		# Check version for backwards compatibility
		var file_version = "1.0.0"  # Default version for old files
		if import_data.has("version"):
			file_version = import_data["version"]
			print("Importing save file version: ", file_version)
		else:
			print("Importing legacy save file (no version field)")
		
		# Handle different versions
		match file_version:
			"1.0.0":
				load_version_1_0_0(import_data)
			"1.1.0":
				load_version_1_1_0(import_data)
			_:
				# Handle unknown versions - try to load as current version
				print("Unknown save file version: ", file_version, " - attempting to load as current version")
				load_version_1_1_0(import_data)
		
		# Add to item list
		var item_list = $UILayer/UI/BrowserPanel/VBox/LevelList
		var domino_count = import_data.get("domino_count", import_data["dominoes"].size() if import_data.has("dominoes") else 0)
		var level_name = import_data.get("level_name", default_level_name)
		var item_text = level_name + " (" + str(domino_count) + " dominoes)"
		
		# Check if this level is already in the list
		var found = false
		for i in range(item_list.item_count):
			if item_list.get_item_text(i) == item_text:
				found = true
				break
		
		# Only add if it's not already in the list
		if not found:
			item_list.add_item(item_text)
			# Select the newly added item
			item_list.select(item_list.item_count - 1)
		
		print("Imported level '", level_name, "' with ", domino_count, " dominoes - Ready to play!")
	else:
		push_error("Failed to parse JSON: ", json.get_error_message())
		
# Slider/SpinBox callback functions
func _on_line_count_value_changed(value: float) -> void:
	line_count = int(value)
	print("Line count: ", line_count)

func _on_line_rotation_value_changed(value: float) -> void:
	line_rotation = value
	print("Line rotation: ", line_rotation)

func _on_curve_radius_value_changed(value: float) -> void:
	curve_radius = value
	print("Curve radius: ", curve_radius)

func _on_curve_angle_value_changed(value: float) -> void:
	curve_angle_deg = value
	print("Curve angle: ", curve_angle_deg)

func _on_curve_full_rotation_value_changed(value: float) -> void:
	curve_full_rotation = value
	print("Curve full rotation: ", curve_full_rotation)

func _on_spiral_size_value_changed(value: float) -> void:
	spiral_radius_end = value
	print("Spiral size: ", spiral_radius_end)

func _on_params_fly_out_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$UILayer/UI/ParamsPanel.position.x = 0
		$UILayer/UI/ParamsPanel/ParamsFlyOut.text = "<"
	else:
		$UILayer/UI/ParamsPanel.position.x = -288
		$UILayer/UI/ParamsPanel/ParamsFlyOut.text = ">"

func _on_ccw_pressed() -> void:
	curve_direction = -1

func _on_cw_pressed() -> void:
	curve_direction = 1
	
func _on_background_color_picker_color_changed(color: Color) -> void:
	world_env.environment.background_color = color # RGB: (0, 0, 1) for blue

func _on_ground_color_color_changed(color: Color) -> void:
	# Get the MeshInstance3D node
	var mesh_instance = $Ground/MeshInstance3D
	
	# Method 1: Create a new StandardMaterial3D and set its color
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material

func _on_domino_color_color_changed(color: Color) -> void:
	domino_material.albedo_color = color

# New functions for save/load buttons
func button_save() -> void:
	save_dominoes()
	print("Save completed!")

func button_load() -> void:
	load_dominoes()
	print("Load completed!")

func _on_browser_fly_out_toggled(toggled_on: bool) -> void:
	if toggled_on:
		$UILayer/UI/BrowserPanel.position.x = 992
		$UILayer/UI/BrowserPanel/BrowserFlyOut.text = ">"
	else:
		$UILayer/UI/BrowserPanel.position.x = 1280
		$UILayer/UI/BrowserPanel/BrowserFlyOut.text = "<"

# Level name input callback - called when user presses Enter or loses focus
func _on_level_name_text_submitted(new_text: String) -> void:
	current_level_name = new_text.strip_edges()
	if current_level_name.is_empty():
		current_level_name = default_level_name
		# Keep the input field empty to show placeholder
		level_name_input.text = ""
	else:
		# Keep the user's input in the field
		level_name_input.text = current_level_name
	print("Level name changed to: ", current_level_name)

# Additional callback for when text changes (optional - for real-time updates)
func _on_level_name_text_changed(new_text: String) -> void:
	# Update the current level name as user types (optional)
	var trimmed_text = new_text.strip_edges()
	if trimmed_text.is_empty():
		current_level_name = default_level_name
	else:
		current_level_name = trimmed_text

func _on_export_pressed() -> void:
	button_export()

func _on_import_pressed() -> void:
	button_import()

func _on_import_text_box_text_set() -> void:
	pass # Replace with function body.
