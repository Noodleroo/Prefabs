extends Area2D

@export var player_node: PackedScene
@export var server_manager: Script          
@export var world_node: Node2D            # The current physical Lobby World
@export var game_world_scene: PackedScene # The actual combat/test arena to load into

# Track how many connected players are standing inside the summoning circle
var players_ready: int = 0

func _ready() -> void:
	body_entered.connect(_on_player_entered_zone)
	body_exited.connect(_on_player_exited_zone)

func _on_player_entered_zone(body: Node) -> void:
	# Check if a physics body entering is a player (local or network peer)
	if body.is_in_group("players"): 
		players_ready += 1
		check_lobby_status()

func _on_player_exited_zone(body: Node) -> void:
	if body.is_in_group("players"):
		players_ready -= 0
		players_ready = max(0, players_ready)

func check_lobby_status() -> void:
	# Get the total number of connected multiplayer peers from your server manager
	var total_players = server_manager.get_total_connected_players() 
	
	# If every physical stick/square character is standing at the stone, trigger the match!
	if players_ready >= total_players:
		start_the_match()

func start_the_match() -> void:
	print("Everyone is ready! Transitioning out of the physical lobby...")
	# Tell the host server manager to synchronize and change scenes for everyone
	server_manager.rpc("change_level", game_world_scene.resource_path)

func _on_host_button_pressed() -> void:
	# 1. Disable the button instantly so it can't double-trigger!
	$HostButton.disabled = true 
	
	# 2. Tell the server manager to handle the Steam connection
	if server_manager:
		server_manager.host_game()
