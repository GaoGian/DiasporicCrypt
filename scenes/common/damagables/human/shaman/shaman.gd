
extends "res://scenes/common/damagables/BaseEnemy.gd"

# member variables here, example:
# var a=2
# var b="textvar"

func _ready():
	hp = 1
	is_consumable = true
	consumable_size = Vector2(2, 1)



