extends Area2D
	   
@export var world_node: Node2D            
@export var lobby_screen_ui: Control    

# Tracks if Quadle is currently standing inside the stone's area
var player_is_inside: bool = false

func _ready() -> void:
	# Connect BOTH entry and exit signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.name == "Player" or body.is_in_group("players") or body is CharacterBody2D:
		body.add_to_group("on_summoning_stone")
		player_is_inside = true
		print("Quadle stepped onto the stone. Press SPACE to invite friends!")

func _on_body_exited(body: Node) -> void:
	if body.name == "Player" or body.is_in_group("players") or body is CharacterBody2D:
		if body.is_in_group("on_summoning_stone"):
			body.remove_from_group("on_summoning_stone")
		player_is_inside = false
		print("Quadle left the summoning stone.")

func _input(event: InputEvent) -> void:
	if player_is_inside and event.is_action_pressed("Jump"):
		print("Space intercepted by stone! Triggering overlay...")
		
		# This now successfully stops the input from reaching Quadle's movement loop!
		get_viewport().set_input_as_handled() 
		
		trigger_steam_invite()

func trigger_steam_invite() -> void:
	if ServerManager and ServerManager.has_method("get_lobby_id"):
		var lobby_id = ServerManager.get_lobby_id()
		print(lobby_id)
		
		if lobby_id != 0:
			Steam.activateGameOverlayInviteDialog(lobby_id)
			if lobby_screen_ui:
				lobby_screen_ui.visible = true
		else:
			print("Steam Check: No active Lobby ID found to invite friends to!")
