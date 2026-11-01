extends SceneTree

var game
var role := "no_room"
var epoch := 0
var restarted := false
var ready_printed := false
var raid_time := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): role=arg.trim_prefix("--case=")
	call_deferred("setup")

func setup() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://matching_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	game.loadout.ammo_packs=2
	game.loadout.medkits=2
	game.session.wait_seconds=0.5 if role=="no_room" else 2.5
	if role=="discovery_host": game.session._host()
	else: game.session.begin_matchmaking()
	epoch=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if not is_instance_valid(game): return false
	var session=game.session
	if Time.get_ticks_msec()-epoch>8000:
		print("NET FAIL "+role+" phase="+session.phase)
		quit(1)
		return false
	if role=="discovery_host" and not ready_printed and session.phase=="waiting":
		print("NET READY "+role)
		ready_printed=true
	if role=="no_room" and not restarted and Time.get_ticks_msec()-epoch>200:
		assert(session.phase=="discovering")
		session.cancel()
		assert(session.phase=="idle" and game.state=="menu")
		assert(session.discovery==null and session.members.is_empty())
		session.begin_matchmaking()
		restarted=true
		epoch=Time.get_ticks_msec()
	if not session.running: return false
	if raid_time==0:
		assert(session.actors.size()==6)
		var humans:=0
		for profile in session.members.values():
			if not profile.get("bot",false): humans+=1
		assert(humans==(1 if role=="no_room" else 2))
		if role=="discovery_client": assert(not session.discovered_address.is_empty(),"The room must be found by UDP broadcast")
		if role=="no_room":
			assert(restarted and Time.get_ticks_msec()-epoch>1200,"No room must lead through discovery, lobby wait and AI fill")
		raid_time=Time.get_ticks_msec()
	if Time.get_ticks_msec()-raid_time>(800 if role=="discovery_host" else 300):
		print("NET PASS "+role+": automatic LAN discovery, human priority, cancellation and no-room AI fallback")
		session.leave()
		if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
		quit()
	return false
