extends Node
## ENet authority, LAN matchmaking and shared raid state. RPCs never accept damage,
## positions, inventory contents or successful extraction supplied by a client.

const CAPACITY := 6
const DEFAULT_PORT := 24570
const DISCOVERY_PORT := 24571
const PROTOCOL := "greyline-raid-5-open-deployment"
const WAIT_SECONDS := 8.0
const SPAWNS := [Vector3(-76,0.2,86),Vector3(77,0.2,88),Vector3(-97,0.2,-80),Vector3(91,0.2,-79),Vector3(-99,0.2,26),Vector3(26,0.2,89)]
const BotBrain = preload("res://scripts/raid_bot.gd")
var game
var phase := "idle"
var running := false
var applying_action := false
var applying_result := false
var context_peer := 0
var server_address := ""
var nickname := ""
var port := DEFAULT_PORT
var discovery_port := DISCOVERY_PORT
var dedicated := false
var wait_seconds := WAIT_SECONDS
var lobby_left := WAIT_SECONDS
var phase_time := 0.0
var actors: Dictionary = {}
var members: Dictionary = {}
var searches: Dictionary = {}
var extraction: Dictionary = {}
var outcomes: Dictionary = {}
var last_input: Dictionary = {}
var action_times: Dictionary = {}
var sequence := 0
var snapshot_clock := 0.0
var lobby_clock := 0.0
var last_snapshot := -1
var container_versions: Dictionary = {}
var inventory_versions: Dictionary = {}
var server_reset_left := -1.0
var discovery: PacketPeerUDP
var discovered_address := ""
var discovery_clock := 0.0
var booting := false
var closing := false
var settings: AcceptDialog
var status_text := "真人优先 · 等待后 AI 补位"

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_lost)
	multiplayer.peer_disconnected.connect(_peer_left)
	nickname = "行者%04d" % randi_range(1000,9999)

func configure_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): server_address=arg.trim_prefix("--server=")
		if arg.begins_with("--port="): port=clampi(int(arg.trim_prefix("--port=")),1024,65535)
		if arg.begins_with("--discovery-port="): discovery_port=clampi(int(arg.trim_prefix("--discovery-port=")),1024,65535)
		if arg.begins_with("--nickname="): nickname=arg.trim_prefix("--nickname=").left(16)
		if arg.begins_with("--match-wait="): wait_seconds=clampf(float(arg.trim_prefix("--match-wait=")),0.5,60)
		if arg=="--dedicated": dedicated=true
	if dedicated:
		game.smoke_mode=true
		game.profile_path="user://dedicated_unused.json"
		call_deferred("_host")
	elif "--auto-match" in OS.get_cmdline_user_args():
		call_deferred("begin_matchmaking")

func is_authority() -> bool:
	return multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.is_server()

func begin_matchmaking() -> void:
	if phase!="idle" or game.state!="menu": return
	if not game.can_deploy():
		game.notify("机密行动战备值不足",4)
		return
	game.state="matching"
	phase_time=0
	game.set_capture()
	if not server_address.is_empty():
		_connect_to(server_address)
		return
	phase="discovering"
	status_text="正在寻找同一网络中的真人房间…"
	discovery=PacketPeerUDP.new()
	discovery.set_broadcast_enabled(true)
	discovery.bind(0)
	discovery.set_dest_address("255.255.255.255",discovery_port)
	discovery.put_packet((PROTOCOL+"|find|"+game.raid_mode).to_utf8_buffer())

func _connect_to(address: String) -> void:
	_close_discovery()
	phase="connecting"
	phase_time=0
	status_text="正在连接 %s:%d" % [address,port]
	var peer:=ENetMultiplayerPeer.new()
	var error:=peer.create_client(address,port)
	if error!=OK:
		fail("无法连接服务器，请检查地址和端口")
		return
	multiplayer.multiplayer_peer=peer

func _host() -> void:
	_close_discovery()
	var peer:=ENetMultiplayerPeer.new()
	var error:=peer.create_server(port,CAPACITY+4)
	if error!=OK:
		if not dedicated and server_address.is_empty():
			_connect_to("127.0.0.1")
		else: fail("无法创建房间：UDP 端口 %d 被占用" % port)
		return
	multiplayer.multiplayer_peer=peer
	phase="waiting"
	game.state="matching"
	phase_time=0
	lobby_left=wait_seconds
	members.clear()
	if not dedicated:
		var profile:=local_profile()
		profile.erase("safe_boxes")
		members[1]=profile
	status_text="房间已就绪 · 正在等待真人加入"
	discovery=PacketPeerUDP.new()
	if discovery.bind(discovery_port)!=OK:
		discovery.close()
		discovery=null

func _connected() -> void:
	phase="waiting"
	phase_time=0
	register.rpc_id(1,local_profile(),PROTOCOL,game.raid_mode)

func local_profile() -> Dictionary:
	game.safe_boxes.refresh_season()
	return {"name":nickname,"loadout":game.deployment_loadout(),"builds":game.weapon_builds.duplicate(true),"safe_boxes":game.safe_boxes.serialize(),"safe_box_id":game.safe_boxes.equipped,"safe_season":game.safe_boxes.season}

@rpc("any_peer","call_remote","reliable")
func register(profile: Dictionary, protocol: String, mode: String) -> void:
	if not is_authority(): return
	var peer:=multiplayer.get_remote_sender_id()
	if protocol!=PROTOCOL or mode!=game.raid_mode or phase!="waiting" or members.size()>=CAPACITY:
		rejected.rpc_id(peer,"房间已开局、已满或行动等级不同，请重新匹配")
		return
	var clean:=sanitize_profile(profile)
	if clean.is_empty():
		rejected.rpc_id(peer,"战备数据无效，无法加入")
		return
	members[peer]=clean
	lobby_clock=0.5

func sanitize_profile(profile: Dictionary) -> Dictionary:
	if not profile.get("loadout") is Dictionary or not profile.get("builds",{}) is Dictionary: return {}
	var source: Dictionary=profile.loadout
	var clean: Dictionary={"weapon":clampi(int(source.get("weapon",-1)),-1,7),"ammo_packs":maxi(int(source.get("ammo_packs",0)),0),"medkits":maxi(int(source.get("medkits",0)),0)}
	for slot in ["armor","helmet"]:
		var id:=str(source.get(slot,""))
		var item: Dictionary=game.EquipmentData.gear_item(id)
		clean[slot]=id if str(item.get("slot",""))==slot else ""
	var builds: Dictionary={}
	var index:=int(clean.weapon)
	builds[str(index)]=game.WeaponModsData.sanitize(index,profile.get("builds",{}).get(str(index),{}))
	var readiness:=int(game.WeaponModsData.weapon(index,builds[str(index)]).get("value",0))
	for slot in ["armor","helmet"]: readiness+=int(game.EquipmentData.gear_item(clean[slot]).get("value",0))
	readiness+=clean.ammo_packs*int(game.EquipmentData.gear_item("ammo_pack").get("value",0))+clean.medkits*int(game.EquipmentData.gear_item("medkit").get("value",0))
	if game.raid_mode=="机密" and readiness<game.CLASSIFIED_READINESS: return {}
	var boxes=game.SafeBoxes.new()
	boxes.restore(profile.get("safe_boxes",{}) if profile.get("safe_boxes",{}) is Dictionary else {})
	return {"name":str(profile.get("name","行者")).strip_edges().left(16),"loadout":clean,"builds":builds,"bot":false,"safe_box_id":boxes.equipped,"safe_season":boxes.season}

@rpc("authority","call_remote","reliable")
func rejected(reason: String) -> void:
	fail(reason)

func _process(delta: float) -> void:
	phase_time+=delta
	if phase=="discovering":
		_poll_discovery()
		if not discovered_address.is_empty(): _connect_to(discovered_address)
		elif phase_time>=1.0: _host()
	elif phase=="connecting" and phase_time>5.0: fail("连接超时 · 检查服务器地址与 UDP 端口")
	elif phase=="waiting":
		if is_authority():
			_poll_discovery()
			if not members.is_empty(): lobby_left=maxf(0,lobby_left-delta)
			lobby_clock+=delta
			if lobby_clock>=0.25:
				lobby_clock=0
				lobby_update.rpc(members,lobby_left)
			if not members.is_empty() and (lobby_left<=0 or members.size()>=CAPACITY): launch()
		elif phase_time>15 and members.is_empty(): fail("房间没有响应，请重新匹配")
	if not running: return
	if is_authority():
		game.raid_left=maxf(0,game.raid_left-delta)
		for id in actors:
			var actor: RaidPlayer=actors[id]
			if actor.finished: continue
			if id!=1 and id>0 and not members[id].get("bot",false) and Time.get_ticks_msec()-int(last_input.get(id,Time.get_ticks_msec()))>650: actor.remote_input={}
			advance_remote_search(id,delta)
			var index:=-1
			for i in range(2):
				if i==1 and game.RAID_LENGTH-game.raid_left<60: continue
				if actor.position.distance_to(RaidWorld.EXITS[i])<6: index=i
			extraction[id]=float(extraction.get(id,0))+delta if index>=0 else 0.0
			if id==1 and not dedicated:
				game.extract_index=index
				game.extract_progress=extraction[id]
			if extraction[id]>=10: finish_actor(id,true,"成功撤离潮汐港")
			elif game.raid_left<=0: finish_actor(id,false,"行动超时 · 接应窗口关闭")
		snapshot_clock+=delta
		if snapshot_clock>=1.0/15.0:
			snapshot_clock=0
			broadcast_snapshot()
		if dedicated and not booting and _all_humans_finished():
			if server_reset_left<0: server_reset_left=1.5
			server_reset_left-=delta
			if server_reset_left<=0: _reset_server()

func _poll_discovery() -> void:
	if discovery==null: return
	while discovery.get_available_packet_count()>0:
		var packet:=discovery.get_packet().get_string_from_utf8()
		var address:=discovery.get_packet_ip()
		var sender_port:=discovery.get_packet_port()
		if packet==PROTOCOL+"|find|"+game.raid_mode and is_authority() and phase=="waiting" and members.size()<CAPACITY:
			discovery.set_dest_address(address,sender_port)
			discovery.put_packet((PROTOCOL+"|room|%d" % port).to_utf8_buffer())
		elif packet.begins_with(PROTOCOL+"|room|") and phase=="discovering":
			discovered_address=address
			port=int(packet.get_slice("|",2))

@rpc("authority","call_local","reliable")
func lobby_update(roster: Dictionary, seconds: float) -> void:
	members=roster
	lobby_left=seconds
	status_text="已找到 %d 名真人 · %.0f 秒后出发" % [members.size(),ceil(seconds)]

func launch() -> void:
	if not is_authority() or running or booting: return
	booting=true
	_close_discovery()
	var roster:=members.duplicate(true)
	for profile in roster.values():
		var box: Dictionary=game.SafeBoxes.definition(str(profile.get("safe_box_id",game.SafeBoxes.DEFAULT_ID)))
		if box.get("access","")=="season" and str(profile.get("safe_season",""))!=game.SafeBoxes.current_season(): profile["safe_box_id"]=game.SafeBoxes.DEFAULT_ID
		profile.erase("safe_boxes")
	for i in range(CAPACITY-roster.size()):
		var id:=-i-1
		roster[id]=BotBrain.profile(i,game.raid_mode)
	# Rebuild before publishing the canonical container contents.
	game.start_raid(true)
	running=true
	phase="raid"
	actors.clear()
	container_versions.clear()
	inventory_versions.clear()
	server_reset_left=-1
	searches.clear()
	extraction.clear()
	outcomes.clear()
	sequence=0
	if dedicated:
		game.player.finished=true
		game.player.collision_layer=0
		game.player.visible=false
	var slot:=0
	for id in roster:
		if id==1 and not dedicated:
			actors[id]=game.player
			game.player.position=SPAWNS[slot]
			game.player.network_id=id
		else: spawn_actor(id,roster[id],SPAWNS[slot])
		slot+=1
	members=roster
	var containers:=container_states()
	for id in roster:
		if id in multiplayer.get_peers(): start_match.rpc_id(id,roster,containers)
	booting=false
	game.notify("6 人行动已开始 · 打开背包或菜单时战局继续",5)

@rpc("authority","call_remote","reliable")
func start_match(roster: Dictionary, containers: Array) -> void:
	game.start_raid(true)
	running=true
	phase="raid"
	members=roster
	actors.clear()
	outcomes.clear()
	last_snapshot=-1
	var slot:=0
	for id in roster:
		if id==multiplayer.get_unique_id():
			actors[id]=game.player
			game.configure_safe_box(game.player,str(roster[id].get("safe_box_id",game.SafeBoxes.DEFAULT_ID)))
			game.player.network_id=id
			game.player.position=SPAWNS[slot]
		else: spawn_actor(id,roster[id],SPAWNS[slot])
		slot+=1
	apply_containers(containers)
	for enemy in game.world.enemies: enemy.replica=true
	game.player.camera.make_current()

func spawn_actor(id: int, profile: Dictionary, spawn: Vector3) -> void:
	var actor:=RaidPlayer.new()
	actor.name="Actor_%d" % absi(id)
	actor.game=game
	actor.network_id=id
	actor.is_local=false
	actor.position=spawn
	actor.weapon_index=int(profile.loadout.weapon)
	# equip() reads a per-actor build, never another participant's local loadout.
	actor.set_meta("builds",profile.get("builds",{}))
	game.add_child(actor)
	configure_actor(actor,profile.loadout)
	game.configure_safe_box(actor,str(profile.get("safe_box_id",game.SafeBoxes.DEFAULT_ID)))
	actors[id]=actor
	last_input[id]=Time.get_ticks_msec()
	if id<0 and is_authority():
		var brain:=BotBrain.new()
		brain.session=self
		brain.actor=actor
		brain.personality=profile.personality
		actor.add_child(brain)

func configure_actor(actor: RaidPlayer, loadout: Dictionary) -> void:
	actor.configure_protection(loadout)
	actor.meds=int(loadout.medkits)
	actor.reserve=int(loadout.ammo_packs)*120

func send_input(controls: Dictionary) -> void:
	if not running or is_authority(): return
	sequence+=1
	input_frame.rpc_id(1,sequence,controls)

@rpc("any_peer","call_remote","unreliable_ordered",1)
func input_frame(serial: int, controls: Dictionary) -> void:
	if not running or not is_authority(): return
	var id:=multiplayer.get_remote_sender_id()
	if not actors.has(id) or actors[id].finished or serial<=int(actors[id].get_meta("input_serial",-1)): return
	var move=controls.get("move",Vector2.ZERO)
	var yaw:=float(controls.get("yaw",0))
	var pitch:=float(controls.get("pitch",0))
	if not move is Vector2 or not move.is_finite() or not is_finite(yaw) or not is_finite(pitch): return
	actors[id].set_meta("input_serial",serial)
	actors[id].remote_input={"move":move.limit_length(),"yaw":wrapf(yaw,-PI,PI),"pitch":clampf(pitch,-1.4,1.4),"fire":bool(controls.get("fire",false)),"click":maxi(0,int(controls.get("click",0))),"aim":bool(controls.get("aim",false)),"jump":bool(controls.get("jump",false)),"sprint":bool(controls.get("sprint",false))}
	last_input[id]=Time.get_ticks_msec()

func player_command(command: String) -> void:
	if not running: return
	if is_authority(): _player_command(1,command)
	else: command_request.rpc_id(1,command)

@rpc("any_peer","call_remote","reliable",2)
func command_request(command: String) -> void:
	if is_authority(): _player_command(multiplayer.get_remote_sender_id(),command)

func _player_command(id: int, command: String) -> void:
	if not actors.has(id) or actors[id].finished: return
	if command=="reload": actors[id].reload_weapon()
	elif command=="heal": actors[id].heal()

func combatants() -> Array:
	var result: Array=[]
	for actor in actors.values():
		if not actor.finished and actor.health>0: result.append(actor)
	return result

func resolve_shot(actor: RaidPlayer) -> void:
	if not is_authority() or actor.finished or actor.weapon_index<0: return
	var origin:=actor.camera.global_position
	var forward: Vector3=-actor.camera.global_basis.z
	for enemy in game.world.enemies:
		if not enemy.dead and enemy.position.distance_to(actor.position)<float(actor.weapon.noise_radius): enemy.hear_noise(actor.position)
	for other in actors.values():
		for child in other.get_children():
			if child is BotBrain: child.hear_noise(actor.position,float(actor.weapon.noise_radius))
	var endpoint:=origin+forward*float(actor.weapon.range)
	for pellet in range(int(actor.weapon.pellets)):
		var spread:=float(actor.weapon.spread)*(0.26 if actor.aimed else 1.0)
		if Vector2(actor.velocity.x,actor.velocity.z).length()>2: spread*=1.6
		var direction: Vector3=(forward+actor.camera.global_basis.x*randf_range(-spread,spread)+actor.camera.global_basis.y*randf_range(-spread,spread)).normalized()
		var ray:=PhysicsRayQueryParameters3D.create(origin,origin+direction*float(actor.weapon.range),1|2|4,[actor.get_rid()])
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		endpoint=hit.position
		var damage:=float(actor.weapon.damage)*clampf(1-origin.distance_to(endpoint)/float(actor.weapon.range)*0.45,0.55,1)
		var killed:=false
		if hit.collider is RaidEnemy:
			killed=hit.collider.take_hit(damage,endpoint)
		elif hit.collider is RaidPlayer:
			var victim: RaidPlayer=hit.collider
			victim.take_damage(damage,endpoint.y-victim.position.y>1.48)
			killed=victim.health<=0
		else: game.impact(endpoint,hit.normal)
		if hit.collider is RaidEnemy or hit.collider is RaidPlayer:
			actor.hit_flash=0.18
			if killed: actor.raid_kills+=1
	if actor.is_local: game.kills=actor.raid_kills
	shot_event.rpc(actor.network_id,origin,endpoint)

@rpc("authority","call_local","unreliable",3)
func shot_event(id: int, origin: Vector3, endpoint: Vector3) -> void:
	if not running: return
	game.tracer(origin,endpoint,Color("ffe2a3"))
	if actors.has(id): actors[id].shot_flash=0.08
	if id!=multiplayer.get_unique_id() and is_instance_valid(game.player):
		game.player.hear_sound(origin,"shot",float(actors[id].weapon.noise_radius) if actors.has(id) else 42.0)

@rpc("authority","call_remote","unreliable",3)
func guard_shot(origin: Vector3, endpoint: Vector3) -> void:
	if not running or not is_instance_valid(game.player): return
	game.tracer(origin,endpoint,Color("e3a577"))
	game.player.hear_sound(origin,"shot",42.0)

func container_states() -> Array:
	var result: Array=[]
	for chest in game.world.loot:
		var items: Array=chest.get_meta("items")
		for item in items:
			if not item.has("net_uid"): item["net_uid"]="%d:%d" % [game.world.loot.find(chest),randi()]
		result.append({"index":result.size(),"items":items.duplicate(true),"revealed":chest.get_meta("revealed"),"elapsed":chest.get_meta("search_elapsed")})
	return result

func apply_containers(containers: Array) -> void:
	for data in containers:
		var index:=int(data.index)
		if index<0 or index>=game.world.loot.size(): continue
		var chest: Node3D=game.world.loot[index]
		chest.set_meta("items",data.items)
		chest.set_meta("revealed",data.revealed)
		chest.set_meta("search_elapsed",data.elapsed)
		chest.set_meta("searched",data.items.is_empty())
		chest.get_node("Indicator").material_override=game.world.mats.dark if data.items.is_empty() else game.world.mats.glow

@rpc("authority","call_remote","reliable",2)
func container_update(changes: Array) -> void:
	if running: apply_containers(changes)

func open_search(index: int) -> void:
	if is_authority(): _open_search(1,index)
	else: search_request.rpc_id(1,index)

@rpc("any_peer","call_remote","reliable",2)
func search_request(index: int) -> void:
	if is_authority(): _open_search(multiplayer.get_remote_sender_id(),index)

func _open_search(id: int, index: int) -> void:
	if not actors.has(id) or actors[id].finished or index<0 or index>=game.world.loot.size(): return
	var actor: RaidPlayer=actors[id]
	var chest: Node3D=game.world.loot[index]
	if actor.position.distance_to(chest.position)>3: return
	var ray:=PhysicsRayQueryParameters3D.create(actor.camera.global_position,chest.position,1)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and not chest.is_ancestor_of(hit.collider): return
	searches[id]={"index":index,"paused":false}
	if id==1 and not dedicated: search_opened(index)
	elif id in multiplayer.get_peers(): search_opened.rpc_id(id,index)

@rpc("authority","call_remote","reliable",2)
func search_opened(index: int) -> void:
	game.search_container=game.world.loot[index]
	game.search_paused=false
	game.inspected_index=-1
	game.overlay="search"
	game.set_capture()

func sync_search_state() -> void:
	if not running: return
	var index: int=game.world.loot.find(game.search_container) if is_instance_valid(game.search_container) else -1
	if is_authority(): _search_state(1,index,game.overlay=="search" and not game.search_paused)
	else: search_state.rpc_id(1,index,game.overlay=="search" and not game.search_paused)

@rpc("any_peer","call_remote","reliable",2)
func search_state(index: int, enabled: bool) -> void:
	if is_authority(): _search_state(multiplayer.get_remote_sender_id(),index,enabled)

func _search_state(id: int, index: int, enabled: bool) -> void:
	if searches.has(id) and searches[id].index==index: searches[id].paused=not enabled

func advance_remote_search(id: int, delta: float) -> void:
	if not searches.has(id) or searches[id].paused: return
	var chest: Node3D=game.world.loot[searches[id].index]
	if actors[id].position.distance_to(chest.position)>3:
		searches.erase(id)
		return
	# Shared discovery advances once per chest, even if several players search it.
	if int(chest.get_meta("search_tick",-1))==Engine.get_process_frames(): return
	chest.set_meta("search_tick",Engine.get_process_frames())
	var elapsed:=float(chest.get_meta("search_elapsed"))+delta
	var revealed:=int(chest.get_meta("revealed"))
	var duration:=float(game.ItemsData.CONTAINERS[chest.get_meta("kind")].time)
	while elapsed>=duration and revealed<chest.get_meta("items").size():
		elapsed-=duration
		revealed+=1
	chest.set_meta("revealed",revealed)
	chest.set_meta("search_elapsed",elapsed)

func item_action(command: String, index: int=-1) -> bool:
	var source:=str(game.inspected_source)
	var selected: int=game.inspected_index if index<0 else index
	var uid:=""
	if command=="take" and is_instance_valid(game.search_container):
		var contents: Array=game.search_container.get_meta("items")
		if selected<0 or selected>=contents.size(): return false
		uid=str(contents[selected].get("net_uid",""))
	elif source in ["bag","safe"]:
		var items: Array=game.player.inventory if source=="bag" else game.player.safe_inventory
		if selected>=0 and selected<items.size(): uid=str(items[selected].get("net_uid",""))
	if is_authority(): return perform_item(1,command,source,selected,uid)
	item_request.rpc_id(1,command,source,selected,uid)
	return false # Clients wait for the authoritative inventory snapshot.

@rpc("any_peer","call_remote","reliable",2)
func item_request(command: String, source: String, index: int, uid: String) -> void:
	if is_authority(): perform_item(multiplayer.get_remote_sender_id(),command,source,index,uid)

func perform_item(id: int, command: String, source: String, index: int, uid: String) -> bool:
	if not running or not actors.has(id) or actors[id].finished: return false
	if command not in ["take","take_all","secure","rotate","use_item","discard","sort"]: return false
	var actor: RaidPlayer=actors[id]
	var chest: Node3D=game.world.loot[searches[id].index] if searches.has(id) else null
	if command in ["take","take_all"]:
		if not is_instance_valid(chest) or actor.position.distance_to(chest.position)>3: return false
		if command=="take":
			index=-1
			var contents: Array=chest.get_meta("items")
			for i in range(contents.size()):
				if str(contents[i].get("net_uid",""))==uid: index=i
			if index<0: return false
	elif command=="sort": pass
	elif source not in ["bag","safe"]: return false
	else:
		var items: Array=actor.inventory if source=="bag" else actor.safe_inventory
		index=-1
		for i in range(items.size()):
			if str(items[i].get("net_uid",""))==uid: index=i
		if index<0: return false
	# Existing grid/weight/consumable rules execute synchronously on the authority.
	var saved: Array=[game.player,game.state,game.overlay,game.search_container,game.inspected_source,game.inspected_index]
	game.player=actor
	game.state="raid"
	game.overlay="search"
	game.search_container=chest
	game.inspected_source=source
	game.inspected_index=index
	applying_action=true
	context_peer=id if id!=1 else 0
	var result:=true
	match command:
		"take": result=game.take_loot(index)
		"take_all": game.take_all_loot()
		"secure": game.move_secure()
		"rotate": game.rotate_item()
		"use_item": game.use_item()
		"discard": game.inspected_items().remove_at(index)
		"sort": game.sort_bag()
	game.player=saved[0]
	game.state=saved[1]
	game.overlay=saved[2]
	game.search_container=saved[3]
	game.inspected_source=saved[4]
	game.inspected_index=-1
	context_peer=0
	applying_action=false
	return result

func request_finish(success: bool, reason: String) -> void:
	# Only an abort may originate from a client. Extraction is measured here.
	if is_authority():
		if not success: finish_actor(1,false,reason)
	else: abort_request.rpc_id(1)

@rpc("any_peer","call_remote","reliable",2)
func abort_request() -> void:
	if is_authority(): finish_actor(multiplayer.get_remote_sender_id(),false,"主动结束行动")

func finish_actor(id: int, success: bool, reason: String) -> void:
	if not actors.has(id) or actors[id].finished: return
	var actor: RaidPlayer=actors[id]
	actor.finished=true
	actor.collision_layer=0
	actor.velocity=Vector3.ZERO
	actor.remote_input={}
	searches.erase(id)
	outcomes[id]={"success":success,"reason":reason}
	if is_instance_valid(actor.body_model): actor.body_model.visual.rotation.x=-PI/2 if not success else 0
	if id==1 and not dedicated: apply_result(actor_state(actor),success,reason)
	elif id in multiplayer.get_peers(): apply_result.rpc_id(id,actor_state(actor),success,reason)

@rpc("authority","call_remote","reliable",2)
func apply_result(data: Dictionary, success: bool, reason: String) -> void:
	if game.state!="raid": return
	apply_actor(game.player,data)
	applying_result=true
	game.kills=int(data.kills)
	game.shots=int(data.shots)
	game.finish_raid(success,reason)
	applying_result=false

func actor_state(actor: RaidPlayer) -> Dictionary:
	return {"id":actor.network_id,"pos":actor.position,"yaw":actor.rotation.y,"vel":actor.velocity,"hp":actor.health,"armor":actor.armor,"helmet":actor.helmet,"ammo":actor.ammo,"reserve":actor.reserve,"meds":actor.meds,"stamina":actor.stamina,"reload":actor.reload_left,"heal":actor.heal_left,"finished":actor.finished,"bag":actor.inventory.duplicate(true),"safe":actor.safe_inventory.duplicate(true),"safe_box_id":actor.safe_box_id,"kills":actor.raid_kills,"shots":actor.raid_shots,"extract":float(extraction.get(actor.network_id,0)),"hit":actor.hit_flash}

func broadcast_snapshot() -> void:
	sequence+=1
	# Numeric state fits below ENet's MTU; float64 preserves random peer IDs.
	var public:=PackedFloat64Array()
	for actor in actors.values():
		public.append_array(PackedFloat64Array([actor.network_id,actor.position.x,actor.position.y,actor.position.z,actor.rotation.y,actor.velocity.x,actor.velocity.y,actor.velocity.z,actor.health,actor.armor,float(actor.finished)]))
	var guards:=PackedFloat32Array()
	for enemy in game.world.enemies:
		guards.append_array(PackedFloat32Array([enemy.position.x,enemy.position.y,enemy.position.z,enemy.visual.rotation.y,enemy.health,float(enemy.dead),enemy.velocity.x,enemy.velocity.z]))
	var changes: Array=[]
	for data in container_states():
		var version:=hash([data.items,data.revealed])
		if int(container_versions.get(data.index,-1))!=version:
			changes.append(data)
			container_versions[data.index]=version
	if not changes.is_empty(): container_update.rpc(changes)
	for id in members:
		if id not in multiplayer.get_peers() or not actors.has(id): continue
		var actor: RaidPlayer=actors[id]
		var version:=hash([actor.inventory,actor.safe_inventory])
		if int(inventory_versions.get(id,-1))!=version:
			inventory_update.rpc_id(id,actor.inventory,actor.safe_inventory)
			inventory_versions[id]=version
		var exit_index:=-1
		for i in range(2):
			if i==1 and game.RAID_LENGTH-game.raid_left<60: continue
			if actor.position.distance_to(RaidWorld.EXITS[i])<6: exit_index=i
		var own:=PackedFloat32Array([actor.health,actor.armor,actor.helmet,actor.ammo,actor.reserve,actor.meds,actor.stamina,actor.reload_left,actor.heal_left,float(actor.finished),actor.raid_kills,actor.raid_shots,float(extraction.get(id,0)),actor.hit_flash,exit_index])
		snapshot.rpc_id(id,sequence,game.raid_left,public,guards,own)

@rpc("authority","call_remote","reliable",2)
func inventory_update(bag: Array, safe: Array) -> void:
	if not running: return
	if game.state=="raid" and bag.size()+safe.size()>game.player.inventory.size()+game.player.safe_inventory.size():
		game.audio.play_sound("loot",-16)
	game.player.inventory=bag
	game.player.safe_inventory=safe
	game.inspected_index=-1

@rpc("authority","call_remote","unreliable_ordered",4)
func snapshot(serial: int, seconds: float, public: PackedFloat64Array, guards: PackedFloat32Array, own: PackedFloat32Array) -> void:
	if not running or game.state!="raid" or serial<=last_snapshot: return
	last_snapshot=serial
	game.raid_left=seconds
	var previous_health: float=game.player.health
	for offset in range(0,public.size(),11):
		var id:=int(public[offset])
		if not actors.has(id): continue
		var actor: RaidPlayer=actors[id]
		actor.health=public[offset+8]
		actor.armor=public[offset+9]
		apply_pose(actor,Vector3(public[offset+1],public[offset+2],public[offset+3]),public[offset+4],Vector3(public[offset+5],public[offset+6],public[offset+7]),bool(public[offset+10]))
	for offset in range(0,mini(guards.size(),game.world.enemies.size()*8),8):
		var enemy: RaidEnemy=game.world.enemies[offset/8]
		enemy.position=Vector3(guards[offset],guards[offset+1],guards[offset+2])
		enemy.visual.rotation.y=guards[offset+3]
		enemy.velocity=Vector3(guards[offset+6],0,guards[offset+7])
		if bool(guards[offset+5]) and not enemy.dead: enemy.take_hit(10000,enemy.position)
		enemy.health=guards[offset+4]
	var actor: RaidPlayer=game.player
	if own[0]<previous_health:
		actor.damage_flash=0.5
		game.audio.play_sound("hurt",-19)
	actor.health=own[0]
	actor.armor=own[1]
	actor.helmet=own[2]
	actor.ammo=int(own[3])
	actor.reserve=int(own[4])
	actor.meds=int(own[5])
	actor.stamina=own[6]
	actor.reload_left=own[7]
	actor.heal_left=own[8]
	actor.finished=bool(own[9])
	actor.raid_kills=int(own[10])
	actor.raid_shots=int(own[11])
	actor.hit_flash=own[13]
	game.kills=actor.raid_kills
	game.shots=actor.raid_shots
	game.extract_progress=own[12]
	game.extract_index=int(own[14])

func apply_actor(actor: RaidPlayer, data: Dictionary) -> void:
	actor.health=float(data.hp)
	actor.armor=float(data.armor)
	actor.helmet=float(data.helmet)
	actor.ammo=int(data.ammo)
	actor.reserve=int(data.reserve)
	actor.meds=int(data.meds)
	actor.stamina=float(data.stamina)
	actor.reload_left=float(data.reload)
	actor.heal_left=float(data.heal)
	actor.hit_flash=float(data.hit)
	actor.finished=bool(data.finished)
	if data.has("bag"): actor.inventory=data.bag
	if data.has("safe"): actor.safe_inventory=data.safe
	if data.has("safe_box_id"): game.configure_safe_box(actor,str(data.safe_box_id))
	apply_pose(actor,data.pos,float(data.yaw),data.vel,bool(data.finished))

func apply_pose(actor: RaidPlayer, pos: Vector3, yaw: float, vel: Vector3, done: bool) -> void:
	actor.finished=done
	if actor.is_local:
		if actor.position.distance_to(pos)>0.35: actor.position=actor.position.lerp(pos,0.45) if actor.position.distance_to(pos)<3 else pos
	else:
		actor.snapshot_position=pos
		actor.snapshot_yaw=yaw
		actor.has_snapshot=true
		actor.velocity=vel
	if actor.finished:
		actor.collision_layer=0
		actor.position=pos
		if is_instance_valid(actor.body_model): actor.body_model.visible=actor.health<=0

func _all_humans_finished() -> bool:
	for id in members:
		if id>0 and not members[id].get("bot",false) and not outcomes.has(id): return false
	return true

func _peer_left(id: int) -> void:
	if closing or not is_authority(): return
	if not running:
		members.erase(id)
		return
	if actors.has(id) and not actors[id].finished:
		# A disconnected participant keeps the same body, cargo, HP and position.
		members[id]["bot"]=true
		var brain:=BotBrain.new()
		brain.session=self
		brain.actor=actors[id]
		brain.personality="谨慎"
		actors[id].add_child(brain)
		last_input.erase(id)
	if members.has(id): members[id]["bot"]=true

func _connection_failed() -> void:
	if not closing: fail("服务器连接失败，请检查地址、网络和 UDP 端口")

func _server_lost() -> void:
	if closing: return
	if running and game.state=="raid":
		running=false
		applying_result=true
		game.finish_raid(false,"房主连接中断 · 行动结束")
		applying_result=false
	leave()
	game.notify("与服务器的连接已断开",5)

func fail(reason: String) -> void:
	leave()
	if game.state=="matching": game.state="menu"
	game.set_capture()
	game.notify(reason,5)

func cancel() -> void:
	if phase in ["discovering","connecting","waiting"]:
		leave()
		game.state="menu"
		game.set_capture()

func leave() -> void:
	closing=true
	running=false
	phase="idle"
	_close_discovery()
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
	for actor in actors.values():
		if is_instance_valid(actor) and actor!=game.player: actor.queue_free()
	actors.clear()
	members.clear()
	searches.clear()
	extraction.clear()
	outcomes.clear()
	last_input.clear()
	inventory_versions.clear()
	container_versions.clear()
	discovered_address=""
	closing=false

func _reset_server() -> void:
	leave()
	if is_instance_valid(game.player): game.player.finished=true
	game.state="menu"
	_host()

func _close_discovery() -> void:
	if discovery!=null: discovery.close()
	discovery=null

func show_settings() -> void:
	if is_instance_valid(settings): settings.queue_free()
	settings=AcceptDialog.new()
	settings.title="联机设置"
	settings.dialog_text="留空自动匹配局域网；跨网络填写房主或专用服务器地址。"
	settings.min_size=Vector2i(550,270)
	var box:=VBoxContainer.new()
	var margin:=MarginContainer.new()
	margin.add_theme_constant_override("margin_top",48)
	margin.add_child(box)
	settings.add_child(margin)
	var name_field:=LineEdit.new()
	name_field.placeholder_text="行动代号"
	name_field.text=nickname
	name_field.max_length=16
	box.add_child(name_field)
	var address_field:=LineEdit.new()
	address_field.placeholder_text="服务器 IP / 域名（留空：自动匹配）"
	address_field.text=server_address
	box.add_child(address_field)
	var port_field:=SpinBox.new()
	port_field.min_value=1024
	port_field.max_value=65535
	port_field.value=port
	port_field.prefix="UDP 端口 "
	box.add_child(port_field)
	settings.confirmed.connect(func():
		nickname=name_field.text.strip_edges().left(16)
		if nickname.is_empty(): nickname="行者%04d" % randi_range(1000,9999)
		server_address=address_field.text.strip_edges()
		port=int(port_field.value)
	)
	game.ui.add_child(settings)
	settings.popup_centered()
