extends Control

@onready var player_list_vbox: VBoxContainer = $OverlayPanel/MainVBox/ScoreboardSection/PlayerListVBox
@onready var server_list_vbox: VBoxContainer = $OverlayPanel/MainVBox/VBoxContainer/BrowserHeader/ScrollContainer/ServerListVBox

@onready var overlay_panel: PanelContainer = $OverlayPanel # Make sure this matches your sub-panel node name!

func _ready() -> void:
	visible = false
	if has_node("OverlayPanel"):
		var panel = $OverlayPanel
		panel.visible = false
			
		# Sizing constraints for the outer box
		panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		panel.custom_minimum_size = Vector2(320, 180)
		
		# --- ADDED: FORCE THE INNER VBOX TO FILL THE GREY CONTAINER ---
		var main_vbox = panel.get_node_or_null("MainVBox")
		if main_vbox:
			main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		# Keep your scroll container height caps safe
		var scroll = panel.get_node_or_null("MainVBox/VBoxContainer/BrowserHeader/ScrollContainer")
		if scroll:
			scroll.custom_minimum_size = Vector2(0, 120)
			scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
			
	Steam.lobby_match_list.connect(_on_steam_servers_received)

func _process(_delta: float) -> void:
	var current_focus = get_viewport().gui_get_focus_owner()
	if current_focus is LineEdit:
		return

	if Input.is_action_just_pressed("Toggle_Debug_Overlay"):
		print("[OVERLAY HUD] Tab key pressed! Opening network dashboard...")
		
		# 1. Broadcaster signal to HIDE all other GUIs in the game
		ServerManager.overlay_opened.emit()
		
		visible = true
		if has_node("OverlayPanel"):
			$OverlayPanel.visible = true
			
		_refresh_scoreboard()
		_fetch_active_servers()
		
	elif Input.is_action_just_released("Toggle_Debug_Overlay"):
		print("[OVERLAY HUD] Tab key released! Closing dashboard...")
		
		# 2. Broadcaster signal to RESTORE all other GUIs in the game
		ServerManager.overlay_closed.emit()
		
		visible = false
		if has_node("OverlayPanel"):
			$OverlayPanel.visible = false

func _show_overlay() -> void:
	visible = true
	_refresh_scoreboard()
	_fetch_active_servers()

func _hide_overlay() -> void:
	visible = false

# --- 1. SCOREBOARD LOGIC ---
func _refresh_scoreboard() -> void:
	# Clear out old visual names
	for child in player_list_vbox.get_children():
		child.queue_free()

	var lobby_id = ServerManager.get_lobby_id()
	var host_steam_id: int = 0
	if lobby_id > 0:
		host_steam_id = Steam.getLobbyOwner(lobby_id)

	# Loop through your modular network manager's tracking dictionary
	for player_id in ServerManager.connected_players:
		var player_name = ServerManager.connected_players[player_id]
		var is_host: bool = false

		if lobby_id > 0:
			var current_peer_steam_id: int = 0
			if player_id == multiplayer.get_unique_id():
				current_peer_steam_id = Steam.getSteamID()
			elif ServerManager.peer:
				current_peer_steam_id = ServerManager.peer.get_peer_steam_id(player_id)

			if current_peer_steam_id == host_steam_id or player_id == 1:
				player_name = player_name + " [Host]"
				is_host = true

		var player_label = Label.new()
		player_label.text = "  • " + player_name
		player_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		player_label.add_theme_font_size_override("font_size", 12)

		if is_host:
			player_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0)) # Gold
		else:
			player_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.8)) # Cyan

		player_list_vbox.add_child(player_label)

# --- 2. GLOBAL SERVER BROWSER LOGIC ---
func _fetch_active_servers() -> void:
	for child in server_list_vbox.get_children():
		child.queue_free()
		
	var loading_label = Label.new()
	loading_label.text = "Refreshing Steam master server tags..."
	loading_label.add_theme_font_size_override("font_size", 10)
	server_list_vbox.add_child(loading_label)
	
	# Ask Steam backend globally for your game ID tags
	Steam.addRequestLobbyListDistanceFilter(Steam.LobbyDistanceFilter.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game_name", "quadle_adventure", Steam.LobbyComparison.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_steam_servers_received(lobbies: Array) -> void:
	# Only process if the overlay player screen is currently active
	if not visible: return
	
	for child in server_list_vbox.get_children():
		child.queue_free()
		
	if lobbies.size() == 0:
		var empty_label = Label.new()
		empty_label.text = "No other online servers active right now."
		empty_label.add_theme_font_size_override("font_size", 11)
		server_list_vbox.add_child(empty_label)
		return
		
	for lobby_id in lobbies:
		var server_tag_name = Steam.getLobbyData(lobby_id, "server_tag")
		var current_players = Steam.getNumLobbyMembers(lobby_id)
		var max_players = Steam.getLobbyMemberLimit(lobby_id)
		
		if server_tag_name.strip_edges() == "":
			server_tag_name = "Unnamed Quadle Lobby"
			
		var server_button = Button.new()
		server_button.text = " %s   (%d/%d Players) [ID: %d]" % [server_tag_name, current_players, max_players, lobby_id]
		server_button.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
		server_button.focus_mode = Control.FOCUS_NONE
		server_button.add_theme_font_size_override("font_size", 11)
		
		# Bind clicking the button directly into your existing modular transition flow
		server_button.pressed.connect(func(): 
			_hide_overlay()
			ServerManager.join_game(lobby_id)
		)
		server_list_vbox.add_child(server_button)
