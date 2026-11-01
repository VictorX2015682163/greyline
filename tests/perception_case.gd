extends SceneTree

const BotBrain = preload("res://scripts/raid_bot.gd")
var game
var actor: RaidPlayer
var brain
var wall: StaticBody3D
var epoch := 0
var stage := 0
var stage_time := 0
var observation := Vector3.ZERO

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://perception_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	game.loadout.ammo_packs=2
	game.loadout.medkits=2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="): game.session.port=int(arg.trim_prefix("--port="))
	game.session.wait_seconds=0.5
	game.session._host()
	epoch=Time.get_ticks_msec()

func add_wall() -> void:
	wall=StaticBody3D.new()
	wall.position=Vector3(-76,1.6,81)
	wall.collision_layer=1
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(30,3.2,0.5)
	collision.shape=shape
	wall.add_child(collision)
	game.add_child(wall)

func next_stage() -> void:
	stage+=1
	stage_time=Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if not is_instance_valid(game): return false
	if Time.get_ticks_msec()-epoch>7000:
		print("NET FAIL perception: timeout stage=%d" % stage)
		quit(1)
		return false
	if not game.session.running: return false
	if stage==0:
		actor=game.session.actors[-1]
		for enemy in game.world.enemies:
			enemy.dead=true
			enemy.collision_layer=0
		for other in game.session.actors.values():
			if other==actor or other==game.player: continue
			other.finished=true
			other.collision_layer=0
		actor.set_physics_process(false)
		game.player.set_physics_process(false)
		for child in actor.get_children():
			if child is BotBrain: brain=child
		brain.set_physics_process(false)
		brain.rng.seed=101
		actor.position=Vector3(-76,0.2,86)
		actor.rotation.y=0
		game.player.position=Vector3(-76,0.2,76)
		add_wall()
		next_stage()
	elif stage==1 and Time.get_ticks_msec()-stage_time>250:
		brain.perceive()
		assert(not is_instance_valid(brain.visible_target),"A wall must block target acquisition")
		wall.queue_free()
		game.player.position=Vector3(-76,0.2,98)
		next_stage()
	elif stage==2 and Time.get_ticks_msec()-stage_time>250:
		brain.perceive()
		assert(not is_instance_valid(brain.visible_target),"An unseen participant behind the agent must not be tracked")
		game.player.position=Vector3(-76,0.2,76)
		next_stage()
	elif stage==3 and Time.get_ticks_msec()-stage_time>250:
		brain.perceive()
		assert(brain.visible_target==game.player,"An exposed participant in the field of view must be seen")
		assert(brain.reaction_left>=0.28,"Sight must not produce an instant shot")
		observation=brain.last_seen
		actor.set_physics_process(true)
		brain.set_physics_process(true)
		next_stage()
	elif stage==4 and Time.get_ticks_msec()-stage_time>90:
		assert(actor.raid_shots==0,"The reaction delay must be respected by ordinary weapon input")
		add_wall()
		game.player.position=Vector3(-70,0.2,76)
		next_stage()
	elif stage==5 and Time.get_ticks_msec()-stage_time>400:
		assert(not is_instance_valid(brain.visible_target))
		assert(brain.last_seen.is_equal_approx(observation),"Memory must retain the observation, not follow a hidden target")
		assert(actor.raid_shots==0,"AI must not fire through the new wall")
		brain.heard_left=0
		brain.hear_noise(game.player.position,3)
		assert(brain.heard_left==0,"Distant quiet sounds must not grant information")
		brain.hear_noise(game.player.position,40)
		assert(brain.heard_left>0 and brain.heard_at.distance_to(game.player.position)>0.01)
		assert(not is_instance_valid(brain.visible_target),"Hearing only supplies an uncertain search area")
		print("NET PASS perception: wall occlusion, field of view, reaction delay, visual memory, no wall shooting, uncertain hearing")
		game.session.leave()
		if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
		quit()
	return false
