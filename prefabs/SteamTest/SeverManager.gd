extends Node

const STEAM_APP_ID: int = 480 

var active_lobby_id: int = 0
var is_host: bool = false
var connected_players: Dictionary = {} # Maps: Steam ID (int) -> Name (String)
var spawned_quadles: Dictionary = {}    # Maps: Steam ID (int) -> Node Reference

signal player_list_changed
signal overlay_opened
signal overlay_closed

@export var player_scene: PackedScene = preload("res://SteamTest/player.tscn")

func _ready() -> void:
	_initialize_steam()
	
	# Wire up ONLY the explicit Steamworks signals we need
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.join_requested.connect(_on_lobby_join_requested)

func _process(_delta: float) -> void:
	Steam.run_callbacks()

func _initialize_steam() -> void:
	var is_running: bool = Steam.steamInit(STEAM_APP_ID, true)
	if not is_running:
		print("Steam failed to initialize!")
		return
	if not Steam.loggedOn():
		print("Steam initialized but user is not logged into an account.")
		return
	print("Steam successfully initialized! Username: ", Steam.getPersonaName())

# =============================================================================
# MATCHMAKING & HOSTING PIPELINE
# =============================================================================

func start_hosting_process() -> void:
	if is_host: return
	print("[STEAM] Requesting a new public lobby from Valve...")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, 4)

func _on_lobby_created(connect_result: int, this_lobby_id: int) -> void:
	if connect_result != 1:
		print("[ERROR] Steam Lobby creation failed!")
		return
		
	print("[DEBUG HOST] Lobby created successfully! ID: ", this_lobby_id)
	active_lobby_id = this_lobby_id
	is_host = true
	
	# --- 1. ADD THIS UNIQUE IDENTIFIER DATA TAG TO THE LOBBY ---
	Steam.setLobbyData(this_lobby_id, "game_name", "quadle_adventure")
	
	# Keep your original server tag name
	Steam.setLobbyData(this_lobby_id, "server_tag", Steam.getFriendPersonaName(Steam.getSteamID()) + "'s Server")
	
	_update_lobby_members()

#func search_for_lobbies() -> void:
	#print("[MATCHMAKING] Querying active lobby directories worldwide...")
	#connected_players.clear()
	#
	## --- 2. FORCE STEAM TO ONLY SEARCH FOR LOBBIES WITH YOUR EXACT GAME TAG ---
	## This cuts through the Spacewar noise instantly!
	#Steam.addRequestLobbyListStringFilter("game_name", "quadle_adventure", Steam.LOBBY_COMPARISON_EQUAL)
	#
	## Tell Steam to search globally
	#Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	#
	## Fire the query
	#Steam.requestLobbyList()

func _on_lobby_match_list(lobbies: Array) -> void:
	print("[MATCHMAKING] Received server list from Steam: ", lobbies)
	
	if not lobbies.is_empty():
		# Grab the first available lobby ID found (the host) and force join it!
		var host_lobby_id = lobbies[0]
		print("[SANDBOX BYPASS] Host found! Force joining lobby: ", host_lobby_id)
		join_game(host_lobby_id)
	else:
		print("[MATCHMAKING] No active lobbies found. Try searching again.")

func check_instance_and_force_join() -> void:
	if OS.has_feature("editor"):
		var args = OS.get_cmdline_args()
		for arg in args:
			# If this is our sandboxed Instance 2, look for an active host to latch onto
			if "instance=1" in arg or "instance-id=2" in arg:
				print("[SANDBOX BYPASS] Instance 2 detected. Waiting 3 seconds for Host to build room...")
				await get_tree().create_timer(3.0).timeout
				
				print("[SANDBOX BYPASS] Force-triggering global matchmaking query...")
				#search_for_lobbies()

func join_game(lobby_id: int) -> void:
	print("[STEAM] Attempting to join lobby ID: ", lobby_id)
	Steam.joinLobby(lobby_id)

func _on_lobby_joined(this_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1: # 1 means Success
		print("[ERROR] Failed to join the Steam Lobby.")
		return
		
	print("[STEAM] Successfully joined lobby room ID: ", this_lobby_id)
	active_lobby_id = this_lobby_id
	is_host = (Steam.getLobbyOwner(this_lobby_id) == Steam.getSteamID())
	
	# Instantly rebuild our local player directories and spawn avatars
	_update_lobby_members()

func _on_lobby_join_requested(lobby_id: int, _friend_id: int) -> void:
	print("Steam Overlay invite accepted! Joining lobby ID: ", lobby_id)
	join_game(lobby_id)

# =============================================================================
# STEAM INTERNAL MEMBERSHIP AND SPAWNING CONTROL
# =============================================================================

# This single function handles reading who is in the room and spawning them!
func _update_lobby_members() -> void:
	if active_lobby_id == 0: return
	
	connected_players.clear()
	var current_members_count = Steam.getNumLobbyMembers(active_lobby_id)
	
	for i in range(current_members_count):
		var member_steam_id = Steam.getLobbyMemberByIndex(active_lobby_id, i)
		var member_name = Steam.getFriendPersonaName(member_steam_id)
		
		# Sandbox Safeguard: Enforce pretty developer profiling inside the editor environment
		if member_steam_id != Steam.getLobbyOwner(active_lobby_id):
			if member_name == "" or member_name == "Unknown" or "Quadle_Peer" in member_name:
				member_name = "Noodleroo_dev"
		else:
			if member_name == "" or member_name == "Unknown":
				member_name = "Noodleroo"
				
		# Save them into our clean tracking sheet data sets
		connected_players[member_steam_id] = member_name
		
		# Automatically spawn a character block if they don't have one yet!
		if not spawned_quadles.has(member_steam_id):
			_spawn_quadle(member_steam_id)
			
	player_list_changed.emit()

func _spawn_quadle(steam_id: int) -> void:
	var current_scene = get_tree().current_scene
	if current_scene.has_node(str(steam_id)):
		return
		
	var new_player = player_scene.instantiate()
	new_player.name = str(steam_id)
	
	current_scene.add_child(new_player)
	spawned_quadles[steam_id] = new_player
	print("[STEAM SPAWNER] Created clean Quadle avatar for account ID: ", steam_id)

func get_lobby_id() -> int:
	return active_lobby_id

func leave_and_close_lobby() -> void:
	if active_lobby_id > 0:
		Steam.leaveLobby(active_lobby_id)
		active_lobby_id = 0
		is_host = false
		connected_players.clear()
		for child in spawned_quadles.values():
			if is_instance_valid(child): child.queue_free()
		spawned_quadles.clear()
		player_list_changed.emit()
