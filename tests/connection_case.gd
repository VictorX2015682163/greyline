extends SceneTree
const BotBrain = preload("res://scripts/raid_bot.gd")

var game
var role := "takeover_host"
var port := 24684
var epoch := 0
var raid_epoch := 0
var ready_printed := false
var saw_raid := false
var remote_id := 0
var takeover_start := Vector3.ZERO
var takeover_time := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): role=arg.trim_prefix("--case=")
		if arg.begins_with("--port="): port=int(arg.trim_prefix("--port="))
	call_deferred("setup")

func setup() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://connection_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	game.loadout.ammo_packs=2
	game.loadout.medkits=2
	game.session.port=port
	game.session.wait_seconds=1.5
	if role=="takeover_host": game.session._host()
	elif role!="dedicated":
		game.session.server_address="127.0.0.1"
		game.session.begin_matchmaking()
	epoch=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if not is_instance_valid(game): return false
	var session=game.session
	if Time.get_ticks_msec()-epoch>18000:
		print("NET FAIL "+role+" timeout "+session.phase)
		quit(1)
		return false
	if not ready_printed and session.phase=="waiting":
		print("NET READY "+role)
		ready_printed=true
	if role=="dedicated" and saw_raid and session.phase=="waiting" and session.members.is_empty():
		print("NET PASS dedicated: empty lobby waits for humans, six slots, result delivery, automatic room reset")
		cleanup()
	if not session.running: return false
	if not saw_raid:
		saw_raid=true
		raid_epoch=Time.get_ticks_msec()
		assert(session.actors.size()==6)
		if session.is_authority():
			for id in session.actors:
				if id>1: remote_id=id
			assert(remote_id>1)
			if role=="takeover_host":
				var actor: RaidPlayer=session.actors[remote_id]
				actor.health=61
				var item: Dictionary=game.ItemsData.get_item("bandage")
				item.net_uid="connection:1"
				actor.inventory=[item]
	var raid_elapsed:=Time.get_ticks_msec()-raid_epoch
	if role=="dropout" and raid_elapsed>1200:
		assert(game.player.health==61 and game.player.inventory.size()==1)
		print("NET PASS dropout: connected, authoritative health/cargo, deliberate disconnect")
		cleanup()
	elif role=="takeover_host" and session.members[remote_id].get("bot",false):
		var actor: RaidPlayer=session.actors[remote_id]
		if takeover_time==0:
			assert(actor.health==61 and actor.inventory.size()==1,"AI takeover preserves body and cargo")
			assert(actor.get_child(actor.get_child_count()-1) is BotBrain)
			takeover_time=Time.get_ticks_msec()
			takeover_start=actor.position
		elif Time.get_ticks_msec()-takeover_time>1800:
			assert(actor.position.distance_to(takeover_start)>1,"Replacement brain drives the existing character")
			print("NET PASS takeover_host: real peer disconnect replaced by AI, same body/health/cargo, continued movement")
			cleanup()
	elif role=="dedicated_client":
		if raid_elapsed>1000 and game.state=="raid": game.finish_raid(false,"test abort")
		if game.state=="result":
			assert(not game.result_success)
			print("NET PASS dedicated_client: joined dedicated authority, received result before room reset")
			cleanup()
	return false

func cleanup() -> void:
	game.session.leave()
	if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
	quit()
