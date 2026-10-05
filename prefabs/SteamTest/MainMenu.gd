extends Control

@export var player_list_container: Control 
# --- NEW SERVER BROWSER EXPORTS ---
# Create these nodes in your UI tree and drag them into the Inspector slots!
@export var server_browser_container: Control 
@export var lobby_list_vbox: VBoxContainer 
@export var server_name_input: LineEdit 

@onready var host_button: Button = $PanelContainer/MenuOptions/HostButton
@onready var join_button: Button = $PanelContainer/MenuOptions/JoinButton
@onready var back_button: Button = $PanelContainer/MenuOptions/BackButton
@onready var quit_button: Button = $QuitButton

func _ready() -> void:
	host_button.focus_mode = Control.FOCUS_NONE
	join_button.focus_mode = Control.FOCUS_NONE
	back_button.focus_mode = Control.FOCUS_NONE
	quit_button.focus_mode = Control.FOCUS_NONE 
	
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	quit_button.pressed.connect(_on_quit_pressed) 
	
	back_button.visible = false 
	if player_list_container:
		player_list_container.visible = false
	if server_browser_container:
		server_browser_container.visible = false
		
	# Connect Steam's lobby matchmaking response directly to this UI script
	Steam.lobby_match_list.connect(_on_steam_lobby_match_list)
		
	await get_tree().process_frame
	$PanelContainer.reset_size()
	
	ServerManager.overlay_opened.connect(func(): self.visible = false)
	ServerManager.overlay_closed.connect(func(): self.visible = true)

func _on_host_pressed() -> void:
	_toggle_buttons(false)
	
	if ServerManager:
		# 1. Read the text straight from your LineEdit node
		var typed_name: String = ""
		if server_name_input: # Make sure this matches your LineEdit export variable name!
			typed_name = server_name_input.text.strip_edges()
		
		# 2. Pass that typed text directly into your host function!
		# If it's empty, our network script will automatically handle the player name fallback.
		ServerManager.start_hosting_process()
		
		back_button.visible = true
		host_button.visible = false
		join_button.visible = false
		if server_name_input: 
			server_name_input.visible = false
		
		if player_list_container:
			player_list_container.visible = true

func _on_join_pressed() -> void:
	_toggle_buttons(false)
	back_button.visible = true
	host_button.visible = false
	join_button.visible = false
	if server_name_input: server_name_input.visible = false
	
	# Show the server selection container and clear any old listings
	if server_browser_container:
		server_browser_container.visible = true
	_refresh_lobby_list()

func _refresh_lobby_list() -> void:
	if not lobby_list_vbox: return
	
	for child in lobby_list_vbox.get_children():
		child.queue_free()
		
	print("Searching Steam backend for server tags...")
	# Tell Steam to look globally and match our primary project ID tag
	Steam.addRequestLobbyListDistanceFilter(Steam.LobbyDistanceFilter.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game_name", "quadle_adventure", Steam.LobbyComparison.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_steam_lobby_match_list(lobbies: Array) -> void:
	if not lobby_list_vbox or not server_browser_container or not server_browser_container.visible:
		return
		
	print("Found ", lobbies.size(), " servers online.")
	
	if lobbies.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "No Servers"
		lobby_list_vbox.add_child(empty_label)
		return

	for lobby_id in lobbies:
		# Extract the custom data tags we added during hosting
		var server_tag_name = Steam.getLobbyData(lobby_id, "server_tag")
		var current_players = Steam.getNumLobbyMembers(lobby_id)
		var max_players = Steam.getLobbyMemberLimit(lobby_id)
		
		if server_tag_name.strip_edges() == "":
			server_tag_name = "Unnamed Quadle Lobby"
			
		# Create a UI button for this specific server
		var lobby_button = Button.new()
		lobby_button.text = " %s   (%d/%d Players)" % [server_tag_name, current_players, max_players]
		lobby_button.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
		lobby_button.focus_mode = Control.FOCUS_NONE
		
		# Bind the button press event to launch the join routine
		lobby_button.pressed.connect(func(): _on_server_selected(lobby_id))
		lobby_list_vbox.add_child(lobby_button)

func _on_server_selected(lobby_id: int) -> void:
	print("Connecting via selection screen to lobby ID: ", lobby_id)
	if ServerManager:
		ServerManager.join_game(lobby_id)
		
		if server_browser_container:
			server_browser_container.visible = false
		if player_list_container:
			player_list_container.visible = true

func _on_back_pressed() -> void:
	if ServerManager and ServerManager.has_method("leave_and_close_lobby"):
		ServerManager.leave_and_close_lobby()
		
	back_button.visible = false
	host_button.visible = true
	join_button.visible = true
	if server_name_input: server_name_input.visible = true
	_toggle_buttons(true)
	
	if player_list_container:
		player_list_container.visible = false
	if server_browser_container:
		server_browser_container.visible = false

func _toggle_buttons(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled

func _on_quit_pressed() -> void:
	print("Quit button clicked! Shutting down game gracefully...")
	if ServerManager and ServerManager.has_method("leave_and_close_lobby"):
		ServerManager.leave_and_close_lobby()
	get_tree().quit()
