class_name LevelCompleteUI
extends Control

## Minimal completion message. Levels call present() with their title and
## hide_complete() when the shot is retried.

@onready var label: Label = $Center/Label

var _fade_tween: Tween


func _ready() -> void:
	hide_complete()


func present(title: String = "LEVEL COMPLETE") -> void:
	_kill_tween()

	label.text = title
	modulate.a = 0.0
	show()

	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.18) \
		.set_ease(Tween.EASE_OUT)


## Immediately hides the message, used when the player retries the shot.
func hide_complete() -> void:
	_kill_tween()
	hide()

	if is_node_ready():
		modulate.a = 1.0


func _kill_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
