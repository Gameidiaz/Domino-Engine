extends Camera3D

var move = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if move:
		if Input.is_action_pressed("left"): position.x -= 0.3
		if Input.is_action_pressed("right"): position.x += 0.3
		if Input.is_action_pressed("up"): position.z -= 0.3
		if Input.is_action_pressed("down"): position.z += 0.3
	pass
