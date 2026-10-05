extends Node

func _ready() -> void:
	# CRITICAL SAFETY GATE: Only run window movements if we are running inside the Godot Editor!
	# This ensures your exported game won't violently snap around on a customer's computer.
	if OS.has_feature("editor"):
		# Fetch all arguments Godot uses to launch this window
		var args = OS.get_cmdline_args()
		
		# Iterate through the args list to find what instance number this window is
		for arg in args:
			if "instance" in arg and "=" in arg:
				# Wait one single engine tick to let the OS construct the viewport size boundaries
				await get_tree().process_frame
				
				# Split by "=" instead of "-" because Godot passes it as "--multiline-instance=1"
				var parts = arg.split("=")
				var instance_id = int(parts[1])
				
				# NOTE: Godot's built-in multiple instances are 0-indexed (Instance 1 is 0, Instance 2 is 1).
				# We add 1 here to keep your exact layout logic intact!
				instance_id += 1
				print("[EDITOR SNAP] Detected Editor Window Instance Number: ", instance_id)
				
				# Get the total number of connected physical monitors plugged into your PC graphics card
				var screen_count = DisplayServer.get_screen_count()
				
				if instance_id == 1:
					# Force Instance 1 to stick onto your primary monitor (Screen 0)
					DisplayServer.window_set_current_screen(0)
					# Maximize it
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
					
				elif instance_id == 2 and screen_count > 1:
					print("[EDITOR SNAP] Snapping Instance 2 directly onto your Second Monitor screen!")
					# Force Instance 2 to immediately teleport onto your second monitor (Screen 1)
					DisplayServer.window_set_current_screen(1)
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
					
				break # Exit loop once instance configuration is complete
