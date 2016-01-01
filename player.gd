
extends KinematicBody2D
# the great majority of player behavior and interaction implementation is modelled after this article: http://higherorderfun.com/blog/2012/05/20/the-guide-to-implementing-2d-platformers/comment-page-1/#comments
# please note that this blog link no longer exists, but you might still be able to see it through archive.org

const DEFAULT_GRAVITY = 1
# in order not to jump off 0-31 slopes, keep run speed below 10
const RUN_SPEED = 7
const JUMP_SPEED = 20
const TILE_SIZE = 32
const LADDER_SPEED = 5
# restrict vertical speed to prevent skipping and other weirdness
const SPEED_LIMIT = 50

var position = Vector2()
var current_animation = "idle"
var direction = 1
var falling = false
var accel = DEFAULT_GRAVITY
var sprite_offset = Vector2()
var tilemap
var collision
var animation_player
var jumpPressed = false
var hanging = false
var climbing_platform = false
var climb_platform = null
var climbspeed = 6
var on_ladder = false
var ladder_top = null

func min_array(array):
	if (array.size() == 1):
		return array[0]
	elif (array.size() > 1):
		var min_float = array[0]
		for i in range(1, array.size() - 1):
			min_float = min(array[i], min_float)
		return min_float
	else:
		return null

# slopes have the format slope#-#, where # denotes the 
# position (from the top) of the corner of the slope from left to right
func isSlope(name):
	return name.match("slope*-*")

func getSlopes(space_state):
	var relevantSlopeTile = space_state.intersect_ray(Vector2(get_global_pos().x, get_global_pos().y+sprite_offset.y), Vector2(get_global_pos().x, get_global_pos().y+sprite_offset.y+8), [self], 2147483647, 16)
	
	if (relevantSlopeTile.has("collider")):
		var collider = relevantSlopeTile["collider"]
		if (isSlope(collider.get_name())):
			return collider
	return null
	
func getClimbPlatform(space_state, direction):
	# true = check left side
	# false = check right side
	var platformY = get_global_pos().y - sprite_offset.y + 16
	var relevantTile = null
	if (direction):
		relevantTile = space_state.intersect_ray(Vector2(get_global_pos().x - sprite_offset.x, platformY), Vector2(get_global_pos().x - sprite_offset.x - 16, platformY), [self])
	else:
		relevantTile = space_state.intersect_ray(Vector2(get_global_pos().x + sprite_offset.x, platformY), Vector2(get_global_pos().x + sprite_offset.x + 16, platformY), [self])

	if (relevantTile.has("collider")):
		if(relevantTile["collider"].get_node("climbable") != null):
			return relevantTile["collider"]
	return null

func getLadderTile(space_state):
	var leftX = get_global_pos().x - sprite_offset.x
	var ladderTile = space_state.intersect_ray(Vector2(leftX, get_global_pos().y - sprite_offset.y), Vector2(leftX, get_global_pos().y + sprite_offset.y), [self], 2147483647, 16)
	if (ladderTile.has("collider")):
		var tileName = ladderTile["collider"].get_name()
		if (tileName == "ladder" || tileName == "ladder_top"):
			return ladderTile["collider"]

	var rightX = get_global_pos().x + sprite_offset.x
	ladderTile = space_state.intersect_ray(Vector2(rightX, get_global_pos().y - sprite_offset.y), Vector2(rightX, get_global_pos().y + sprite_offset.y), [self], 2147483647, 16)
	if (ladderTile.has("collider")):
		var tileName = ladderTile["collider"].get_name()
		if (tileName == "ladder" || tileName == "ladder_top"):
			return ladderTile["collider"]
	return null

func snapToLadder(ladder):
	var ladderX = ladder.get_global_pos().x - get_global_pos().x
	move(Vector2(ladderX, 0))

func parseSlopeType(name):
	var values = name.split("slope")
	# slope#-#
	# extract #; first is left corner and last is right corner
	var slopes = values[1].split("-")
	if (slopes[0] == "a" && slopes[1] == "b"):
		return null
	return values[1].split_floats("-")

func closestXTile(direction, desiredX):
	# true = check left side
	# false = check right side
	if (is_colliding()):
		if (get_collision_pos().y > int(get_pos().y - sprite_offset.y) && get_collision_pos().y < int(get_pos().y + sprite_offset.y)):
			return 0
	return desiredX

func closestYTile(tileA, tileB):
	if (!tileA.has("position")):
		return tileB["position"].y
	elif (!tileB.has("position")):
		return tileA["position"].y
	else:
		return min(tileA["position"].y, tileB["position"].y)

func _fixed_process(delta):
	var space = get_world_2d().get_space()
	var space_state = Physics2DServer.space_get_direct_state(space)
	var animation_speed = 1
	
	# step horizontal motion first
	position.y = 0
	var new_animation = current_animation
	var horizontal_motion = false
	# position at character's feet
	var forwardY = get_pos().y + sprite_offset.y
	var relevantSlopeTile = null
	var onSlope = false
	if (!climbing_platform):
		if (Input.is_action_pressed("ui_left")):
			position.x = -min(RUN_SPEED, closestXTile(true, RUN_SPEED))
			new_animation = "run"
			direction = -1
			horizontal_motion = true
		elif (Input.is_action_pressed("ui_right")):
			position.x = min(RUN_SPEED, closestXTile(false, RUN_SPEED))
			new_animation = "run"
			direction = 1
			horizontal_motion = true
		else:
			position.x = 0
			new_animation = "idle"
		
		# disengage hanging on ledge if opposite button is pressed
		if (hanging):
				if ((direction < 0 && climb_platform.get_global_pos().x > get_global_pos().x) || (direction > 0 && climb_platform.get_global_pos().x < get_global_pos().x)):
					hanging = false
					move(Vector2(0, climb_platform.get_global_pos().y + TILE_SIZE/2 - get_pos().y + sprite_offset.y))
					climb_platform = null

		move(position)

		position.x = 0
		
		# check ladder after horizontal movement
		var ladderTile = getLadderTile(space_state)
		
		if (ladderTile != null && ladderTile.get_name() == "ladder_top"):
			ladder_top = ladderTile
		else:
			ladder_top = null
		
		if (on_ladder):
			ladderTile = getLadderTile(space_state)
			if (ladderTile == null):
				on_ladder = false
		
		if (!on_ladder):
			# check slope tiles
			relevantSlopeTile = getSlopes(space_state)
			
			var onZeroSlope = false
			var currentSlopeTile = null
			var b = null
			forwardY = get_pos().y + sprite_offset.y
			if (relevantSlopeTile != null):
				b = parseSlopeType(relevantSlopeTile.get_name())
				if (b != null):
					onSlope = true
					b = parseSlopeType(relevantSlopeTile.get_name())
					# ignore bottom slopes if we're not close enough to them
					if ((b[0] == TILE_SIZE - 1 || b[1] == TILE_SIZE - 1) && (get_global_pos().x < relevantSlopeTile.get_global_pos().x - TILE_SIZE / 2 || get_global_pos().x > relevantSlopeTile.get_global_pos().x + TILE_SIZE / 2)):
						pass
					else:
						var t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE / 2)/TILE_SIZE
						var slopeY = (1 - t) * b[0] + t * b[1]
						
						var slopeAdjustedTileY = relevantSlopeTile.get_global_pos().y - TILE_SIZE / 2 + int(slopeY)
						
						# clamp to slope only if not jumping
						# unfortunately, the extra height from the default jump speed isn't enough to clear 
						# neighboring slopes. Playing with the values yields 5 as sufficient to do so
						if ((forwardY > slopeAdjustedTileY - JUMP_SPEED + 5) || !jumpPressed):
							position.y = slopeAdjustedTileY - forwardY
							move(position)
							
	var climb_vertically = false
	
	# check platform climbing after horizontal movement requested
	if (!on_ladder):
		var platform_check = null
		
		if (!climbing_platform):
			platform_check = getClimbPlatform(space_state, direction == -1)
		
		# clamp to platform if should be hanging
		if (platform_check != null && !climbing_platform && climb_platform == null):
			hanging = true
			var d =  platform_check.get_global_pos().x - direction * TILE_SIZE/2 - get_global_pos().x - direction * sprite_offset.x
			climb_platform = platform_check
			move(Vector2(d, 0))
		
		if (platform_check == null && climb_platform != null && !climbing_platform):
			climb_platform = null
		
		# animate climbing platform
		# move a specific distance in an L shape to climb the platform every fixed function call
		# move up 4 tiles (the height of the character) and then left or right one tile
		# depending on how you choose to animate climbing, this may or may not
		# look very nice. If you have too few frames or don't adjust the vertical position, the
		# character can sometimes look like they're oscillating up and down on the platform
		# vertical motion is delayed until vertical motion checking
		if (climbing_platform):
			if (get_pos().y + sprite_offset.y <= climb_platform.get_global_pos().y - TILE_SIZE/2):
				move(Vector2(climbspeed * direction, 0))
				if ((direction == 1 && get_global_pos().x >= climb_platform.get_global_pos().x) || (direction == -1 && get_global_pos().x <= climb_platform.get_global_pos().x)):
					climb_platform = null
					climbing_platform = false
			else:
				climb_vertically = true
	
	# check vertical motion
	jumpPressed = false
	
	var ladderY = 0
	
	forwardY = get_global_pos().y + sprite_offset.y
	var leftX = get_global_pos().x - sprite_offset.x
	var rightX = get_global_pos().x + sprite_offset.x
	
	# bottom left ray check
	var relevantTileA = space_state.intersect_ray(Vector2(leftX, forwardY), Vector2(leftX, forwardY+16), [self])
	# bottom right ray check
	var relevantTileB = space_state.intersect_ray(Vector2(rightX, forwardY), Vector2(rightX, forwardY+16), [self])

	# check regular blocks
	var normalTileCheck = !relevantTileA.empty() || !relevantTileB.empty()
	
	if (Input.is_action_pressed("ui_up")):
		var ladderTile = getLadderTile(space_state)
		if (ladderTile != null):
			# only allow entering ladder from bottom
			if (!on_ladder && ladderTile.get_name() != "ladder_top"):
				on_ladder = true
				snapToLadder(ladderTile)
			elif (on_ladder):
				if (ladderTile.get_name() == "ladder_top"):
					ladder_top = ladderTile
				if (ladder_top != null):
					if (ladder_top.get_global_pos().y + TILE_SIZE/2 >= get_pos().y + sprite_offset.y):
						on_ladder = false
					else:
						var d = get_pos().y + sprite_offset.y - ladder_top.get_global_pos().y - TILE_SIZE/2
						ladderY = -min(LADDER_SPEED, d)
						snapToLadder(ladder_top)
				else:
					ladderY = -LADDER_SPEED
					snapToLadder(ladderTile)
		
		if (!on_ladder):
			if (!falling && !climbing_platform):
				accel = -JUMP_SPEED
				falling = true
				jumpPressed = true
				if (ladder_top != null):
					print(ladderY)
			if (hanging):
				hanging = false
				climbing_platform = true

	if (Input.is_action_pressed("ui_down")):
		var ladderTile = getLadderTile(space_state)
		if (ladderTile != null):
			# only allow entering ladder if not at the bottom
			if (!on_ladder && (!normalTileCheck || ladder_top != null || ladderTile.get_name() == "ladder_top")):
				on_ladder = true
				snapToLadder(ladderTile)
			elif (on_ladder):
				if (normalTileCheck):
					var closestNormalTileY = closestYTile(relevantTileA, relevantTileB)
					var deltaY = closestNormalTileY - get_pos().y - sprite_offset.y
					if (int(deltaY) > 0):
						snapToLadder(ladderTile)
						ladderY = min(int(deltaY), LADDER_SPEED)
						animation_speed = -1
					else:
						accel = 0
						on_ladder = false
				else:
					snapToLadder(ladderTile)
					ladderY = LADDER_SPEED
					animation_speed = -1
		else:
			falling = true
			on_ladder = false
			# make sure we are really falling
			accel = max(1, accel)
				
		if (hanging && !on_ladder):
			hanging = false

	# don't bother checking regular tiles below character if on ladder
	if (!on_ladder):
		var desiredY = accel
		
		if (falling):
			desiredY += 1
		else:
			desiredY = 1
		
		var s = 1
		
		if (desiredY < 0):
			s = -1
		
		relevantSlopeTile = getSlopes(space_state)
		
		var closestTileY = desiredY
	
		var abSlope = null
	
		if (normalTileCheck):
			closestTileY = closestYTile(relevantTileA, relevantTileB)
	
			closestTileY -= get_pos().y+sprite_offset.y
			closestTileY = int(closestTileY)
	
			# prevent sticking to ceiling
			if (closestTileY == 0):
				if s == -1:
					closestTileY = JUMP_SPEED - 1
				# landed on a platform; not falling anymore
				if s == 1:
					falling = false
		
			# ensure we are falling if not mediated by jumping
			if (abs(desiredY) < abs(closestTileY)):
				falling = true
		forwardY = get_pos().y + sprite_offset.y
		
		# check slope tiles
		if (relevantSlopeTile != null):
			var closestSlopeTile = null
			var t
			var b
			var slopeY = 0
			var closest_level = null
			# find relevant distances to slope tiles
			b = parseSlopeType(relevantSlopeTile.get_name())
			if (b != null):
				t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE/2) / TILE_SIZE
				slopeY = (1 - t) * b[0] + t * b[1]
				if (forwardY <= relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + int(slopeY)):
					closest_level = relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 - forwardY
					b = parseSlopeType(relevantSlopeTile.get_name())
					t = (get_global_pos().x - relevantSlopeTile.get_global_pos().x + TILE_SIZE/2)/TILE_SIZE
					slopeY = (1 - t) * b[0] + t * b[1]
					
					# check that we are really standing on a slope tile
					if (relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY - forwardY < JUMP_SPEED - 1):
						onSlope = true
						falling = false
					
					# don't need to check slope on ceilings
					if (forwardY >= relevantSlopeTile.get_global_pos().y + TILE_SIZE/2):
						closestTileY = forwardY - relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 - TILE_SIZE
					elif (forwardY <= relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY):
						closestTileY = relevantSlopeTile.get_global_pos().y - TILE_SIZE/2 + slopeY - forwardY
						if (jumpPressed):
							closestTileY = desiredY
	
					closestTileY = int(closestTileY)
			else:
				# not standing on a slope. This is just a block whose collision
				# is ignorable when standing on a slope tile next to it.
				abSlope = relevantSlopeTile
				if (abSlope.get_global_pos().y - TILE_SIZE/2 <= forwardY):
					move(Vector2(0, abSlope.get_global_pos().y - TILE_SIZE/2 - forwardY - 1))
					forwardY = get_pos().y + sprite_offset.y
				closestTileY = min(abSlope.get_global_pos().y - TILE_SIZE/2 - forwardY - 1, desiredY)
				closestTileY = int(closestTileY)
				falling = false
		
		# handle standing on a ladder_top tile
		if (ladder_top != null && !normalTileCheck):
			if (ladder_top.get_global_pos().y + TILE_SIZE/2 <= int(forwardY)):
				# in theory, we'd like this to work as is, but without the extra - 2,
				# we run into collisions with neighboring ladder blocks
				# same reason we can't pass between static body tileset tiles with gaps
				# one tile wide
				move(Vector2(0, int(ladder_top.get_global_pos().y + TILE_SIZE/2 - get_pos().y - sprite_offset.y - 2)))
				forwardY = get_pos().y + sprite_offset.y
				falling = false
			closestTileY = min(ladder_top.get_global_pos().y + TILE_SIZE/2 - get_pos().y - sprite_offset.y, desiredY)
			closestTileY = int(closestTileY)
		
		# final falling status check for all kinds of collisions
		if (!normalTileCheck && ((relevantSlopeTile == null || !onSlope) && abSlope == null) && ladder_top == null):
			falling = true
		
		accel = min(min(abs(desiredY), abs(closestTileY)), SPEED_LIMIT) * s
		
		# clamp to platform vertically to prevent falling while hanging with no input
		if (hanging && climb_platform != null):
			accel = climb_platform.get_global_pos().y - TILE_SIZE/2 - get_pos().y + sprite_offset.y
	
		# move character up from climbing ledge
		# see notes in horizontal motion about animation
		if (climb_vertically && climbing_platform):
			#var d = climb_platform.get_global_pos().y - TILE_SIZE/2 - get_pos().y + sprite_offset.y
			accel = -climbspeed
			falling = false
	
		position.y = accel
		
		# check animations
		if (falling):
			if (accel < 0):
				new_animation = "jump"
			else:
				new_animation = "fall"
		
		if (!horizontal_motion):
			if (!falling && ((animation_player.get_current_animation() == "land" && animation_player.is_playing()) || current_animation == "fall")):
				new_animation = "land"
		
		if (climbing_platform || hanging):
			new_animation = "climb"
			if (hanging):
				animation_speed = 0
		
	var motion = position
		
	if (on_ladder):
		direction = 1
		motion.y = ladderY
		new_animation = "ladder"
		if (ladderY == 0):
			animation_speed = 0
	
	get_node("NormalSpriteGroup/"+new_animation).set_scale(Vector2(direction, 1))
	
	move(motion)
	play_animation(new_animation, animation_speed)
	
func _ready():
	collision = get_node("CollisionShape2D")
	sprite_offset = collision.get_shape().get_extents()
	animation_player = get_node("AnimationPlayer")
	climbspeed = animation_player.get_animation("climb").get_length() * 6
	
	set_fixed_process(true)

func load_tilemap(var tilemap_node):
	tilemap = tilemap_node.get_node("tilemap")

func on_ground():
	print("is colliding?")
	#print(ray_ground.is_colliding())
	#print(get_collision_normal())
	#print(get_pos().y + sprite_offset.y)
	print(get_pos().y + sprite_offset.y)
	#return ray_ground.is_colliding() && get_pos().y + sprite_offset.y >= ray_ground.get_collision_point().y - 16
	pass

func play_animation(animation, speed):
	animation_player.set_speed(speed)
	if (current_animation != animation):
		animation_player.play(animation)
		#if (animation == "climb" && hanging):
		#	animation_player.set_speed(0)
		current_animation = animation
	#if (animation == "climb" && climbing_platform):
	#	animation_player.set_speed(1)
	#	if (!animation_player.is_playing()):
	#		animation_player.play()

func loop_jump_animation():
	animation_player.seek(0.1, true)
	
func loop_fall_animation():
	animation_player.seek(0.2, true)