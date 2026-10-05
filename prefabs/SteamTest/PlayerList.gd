extends Control

# Drag your ServerManager node here in the Inspector window

# --- CRITICAL: Make sure you drag your PlayerLabel.tscn file here in the Inspector! ---
@export var player_label_template: PackedScene 

@onready var player_list_box = $PanelContainer/VBoxContainer/PlayerList
@onready var server_title_label: Label = $PanelContainer/VBoxContainer/ServerTitleLabel

func _ready() -> void:
	# Keep your window snapping logic here...
	
	if ServerManager.has_signal("player_list_changed"):
		# Check if the signal is already wired up to this specific function
		if not ServerManager.player_list_changed.is_connected(refresh_player_list):
			ServerManager.player_list_changed.connect(refresh_player_list)
			print("[UI] Successfully connected to ServerManager network signal!")
		else:
			print("[UI] Signal already connected, bypassing duplicate hook safely.")
			
	# Call it once immediately just to populate initial values
	refresh_player_list()

func refresh_player_list() -> void:
	print("[DEBUG UI] refresh_player_list triggered. Active entries count: ", ServerManager.connected_players.size())
	
	# 1. Clear out old labels from the container layout
	for child in player_list_box.get_children():
		player_list_box.remove_child(child)
		child.queue_free()
		
	# 2. Check if the dictionary is empty
	if not ServerManager or ServerManager.connected_players.is_empty():
		_add_fallback_label("Waiting for lobby...")
		if server_title_label:
			server_title_label.text = "Connecting..."
		return
		
	# 3. Fetch True Steam Host Identifiers
	var lobby_id = ServerManager.get_lobby_id()
	var host_steam_id: int = 0
	var room_name: String = "Lobby Room"
	
	if lobby_id > 0:
		host_steam_id = Steam.getLobbyOwner(lobby_id)
		room_name = Steam.getLobbyData(lobby_id, "server_tag")
		
		if room_name.strip_edges() == "":
			room_name = Steam.getFriendPersonaName(host_steam_id) + "'s Server"
	else:
		# Fallback if Steam lobby layers aren't fully active yet
		host_steam_id = Steam.getSteamID()
		room_name = Steam.getFriendPersonaName(host_steam_id) + "'s Server"
			
	if server_title_label:
		server_title_label.text = "Server:\n" + room_name
		
	# 4. SORT BY STEAM ID: Force the True Lobby Owner to the absolute top of the array list
	var sorted_steam_ids: Array = []
	
	if host_steam_id in ServerManager.connected_players:
		sorted_steam_ids.append(host_steam_id)
		
	for steam_id in ServerManager.connected_players:
		if steam_id != host_steam_id:
			sorted_steam_ids.append(steam_id)

	# 5. Loop through our perfectly sorted Steam ID array to paint the text boxes
	for steam_id in sorted_steam_ids:
		var player_name = ServerManager.connected_players[steam_id]
		var is_host: bool = (steam_id == host_steam_id)
		
		# Suffix the badge to the string if they are the lobby owner
		if is_host:
			player_name = player_name + " [Host]"
				
		# 6. Instantiate player entry text labels (using your sizing fix!)
		var label: Label
		if player_label_template:
			label = player_label_template.instantiate()
			if label.label_settings:
				label.label_settings = label.label_settings.duplicate()
		else:
			label = Label.new()
				
		label.text = "• " + player_name
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		label.custom_minimum_size = Vector2(0, 0)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = false
		
		label.add_theme_font_size_override("font_size", 7)
		if label.label_settings:
			label.label_settings.font_size = 7
			
		if is_host:
			var host_color = Color(1.0, 0.84, 0.0) # Gold
			label.add_theme_color_override("font_color", host_color) 
			if label.label_settings:
				label.label_settings.font_color = host_color
		else:
			var client_color = Color(0.0, 1.0, 0.8) # Cyan
			label.add_theme_color_override("font_color", client_color)
			if label.label_settings:
				label.label_settings.font_color = client_color
				
		player_list_box.add_child(label)

	$PanelContainer.reset_size()

func _add_fallback_label(text_content: String) -> void:
	var fallback = Label.new() 
	fallback.text = text_content
	fallback.add_theme_constant_override("font_size", 4) # Keeps backup text small
	player_list_box.add_child(fallback)

func _on_player_list_changed() -> void:
	for child in player_list_box.get_children():
		child.queue_free()
		
	for player_id in ServerManager.connected_players:
		var username = ServerManager.connected_players[player_id]
		
		# Instantiate your stylized mini-scene instead of a generic label
		var new_entry = player_label_template.instantiate()
		new_entry.text = "• " + str(username)
		player_list_box.add_child(new_entry)
