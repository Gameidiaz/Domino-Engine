extends Panel


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_play_pressed() -> void:
	var tween = get_tree().create_tween()
	tween.tween_property($".", "position", Vector2(0, 720), 1).set_trans(Tween.TRANS_SINE)
	pass # Replace with function body.
