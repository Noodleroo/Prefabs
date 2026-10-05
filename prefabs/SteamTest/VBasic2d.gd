extends CharacterBody2D

@onready var sprite = $Sprite2D

const SPEED = 150.0
const JUMP_VELOCITY = -350.0
var color_assigned: bool = false

const LOBBY_COLORS = [
	Color(0.2, 0.6, 1.0),  # 1 (Host): Classic Quadle Blue
	Color(0.9, 0.2, 0.3),  # 2: Vibrant Red
	Color(0.2, 0.8, 0.4),  # 3: Neon Green
	Color(0.9, 0.7, 0.1)   # 4: Sunny Yellow
]

func _ready() -> void:
	# Add the player to the global tracking group we set up earlier
	add_to_group("players")
	
	# Wait one frame for the multiplayer system to assign network IDs
	await get_tree().process_frame
	_assign_network_color()

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta
		
	if Input.is_action_just_pressed("Jump") and is_on_floor():
	# Only jump if we are NOT standing on the summoning stone!
		if not is_in_group("on_summoning_stone"):
			velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("Left", "Right")
	if direction:
		velocity.x = direction * SPEED
		if direction < 0:
			sprite.flip_h = true
		else: sprite.flip_h = false
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func _assign_network_color() -> void:
	# Wait for node tree placement to finalize
	await get_tree().process_frame
	
	var my_steam_id_string = str(Steam.getSteamID())
	
	# If this node's name matches our local machine's Steam account ID, it's US!
	if name == my_steam_id_string:
		if ServerManager.is_host:
			sprite.modulate = LOBBY_COLORS[0] # Host is Blue
			print("Local Host Player assigned color: Blue")
		else:
			sprite.modulate = LOBBY_COLORS[1] # Client is Cyan
			print("Local Client Player assigned color: Cyan")
	else:
		# It belongs to a remote peer! Read the node name index for a mix color
		var peer_steam_id = name.to_int()
		var color_index = peer_steam_id % LOBBY_COLORS.size()
		sprite.modulate = LOBBY_COLORS[color_index]
		print("Remote Peer Steam Node ", name, " assigned color index: ", color_index)
