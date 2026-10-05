extends MultiplayerSpawner

# Drag your separate Player.tscn file directly into this slot in the Inspector
@export var player_scene: PackedScene = preload("res://SteamTest/player.tscn") 
@export var players_container: Node2D

func _ready() -> void:
	# Only the Host server machine is allowed to spawn physical entities into the map
	if not multiplayer.is_server():
		return
		
	# 1. Spawn a visual block for the Host right away
	_spawn_player_character(1)
	
	# 2. Listen for clients joining via Steam P2P and spawn their blocks automatically
	multiplayer.peer_connected.connect(_spawn_player_character)
	multiplayer.peer_disconnected.connect(_despawn_player_character)

func _spawn_player_character(id: int) -> void:
	print("[SPAWNER] Instantiating visual character block for Network ID: ", id)
	
	var new_player = player_scene.instantiate()
	new_player.name = str(id) # Name must match their network ID so the synchronizer tracks it!
	
	# Give them a random starting coordinate on the grass so they don't spawn trapped inside each other
	new_player.position = Vector2(randf_range(100, 300), 200)
	
	# Setting the multiplayer authority gives that specific computer full controls over moving their own block
	new_player.set_multiplayer_authority(id)
	
	players_container.add_child(new_player, true)

func _despawn_player_character(id: int) -> void:
	print("[SPAWNER] Removing character block for disconnected peer ID: ", id)
	var player_to_remove = players_container.get_node_or_null(str(id))
	if player_to_remove:
		player_to_remove.queue_free()
