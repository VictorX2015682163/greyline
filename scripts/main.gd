extends Node3D

const EquipmentData = preload("res://scripts/equipment.gd")
const WeaponModsData = preload("res://scripts/weapon_mods.gd")
const ItemsData = preload("res://scripts/items.gd")
const WeaponMods = preload("res://scripts/weapon_mods.gd")
const Items = preload("res://scripts/items.gd")
const Session = preload("res://scripts/session.gd")
const SafeBoxes = preload("res://scripts/safe_boxes.gd")
const ManualSafePurchase = preload("res://scripts/manual_safe_purchase.gd")

var safe_boxes = SafeBoxes.new()
var manual_safe_purchase = ManualSafePurchase.new()
var safe_purchase_open := false
var safe_purchase_message := ""
var safe_purchase_success := false
var season_check_left := 0.0

const RAID_LENGTH := 720.0
var world: RaidWorld
var player: RaidPlayer
var ui: RaidUI
var audio: RaidAudio
var menu_camera: Camera3D
var state := "menu"
var menu_tab := "deploy"
var raid_mode := "普通"
const CLASSIFIED_READINESS := 60000
var overlay := ""
var selected_weapon := 0
var weapon_builds: Dictionary = {}
var mod_slot := "optic"
var search_container: Node3D
var search_paused := false
var inspected_source := ""
var inspected_index := -1
var stash_filter := "全部"
var stash_page := 0
var market_slot := "armor"
var selected_gear := "armor_1"
var raid_left := RAID_LENGTH
var extract_progress := 0.0
var extract_index := -1
var current_loot: Node3D
var kills := 0
var shots := 0
var message := ""
var message_left := 0.0
var menu_time := 0.0
var result_success := false
var result_reason := ""
var bank := 25000
var stash: Array = []
var owned_gear: Dictionary = {}
var loadout: Dictionary = {
	"weapon": 0,
	"armor": "armor_1",
	"helmet": "helmet_1",
	"ammo_packs": 0,
	"medkits": 0,
}
var raids := 0
var escaped := 0
var storage_warning := ""
var showcase_viewport: SubViewport
var showcase_root: Node3D
var showcase_gun: Node3D
var showcase_texture: ViewportTexture
var last_interaction_scan := 0.0
var start_requested := false
var profile_path := "user://profile.json"
var smoke_mode := false
var session

func _ready() -> void:
	session = Session.new()
	session.name = "Session"
	session.game = self
	add_child(session)
	if "--smoke-test" in OS.get_cmdline_user_args():
		smoke_mode=true
		profile_path="user://smoke_profile_%d.json" % OS.get_process_id()
		if FileAccess.file_exists(profile_path): DirAccess.remove_absolute(profile_path)
	if "--capture-preview" in OS.get_cmdline_user_args():
		smoke_mode=true
		profile_path="user://preview_profile.json"
	elif "--dedicated" in OS.get_cmdline_user_args():
		smoke_mode=true
		profile_path="user://dedicated_unused.json"
	else:
		load_profile()
	safe_boxes.refresh_season()
	world = RaidWorld.new()
	world.raid_mode = raid_mode
	add_child(world)
	menu_camera = Camera3D.new()
	menu_camera.fov = 61
	menu_camera.position = Vector3(142,100,155)
	add_child(menu_camera)
	menu_camera.look_at(Vector3(4,0,-12))
	menu_camera.make_current()
	audio = RaidAudio.new()
	add_child(audio)
	setup_showcase()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = RaidUI.new()
	ui.game = self
	canvas.add_child(ui)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if "--smoke-test" in OS.get_cmdline_user_args():
		call_deferred("run_smoke_test")
	if "--quick-raid" in OS.get_cmdline_user_args():
		call_deferred("start_raid")
	if "--capture-preview" in OS.get_cmdline_user_args():
		call_deferred("capture_preview")
	session.configure_args()

func _input(event: InputEvent) -> void:
	if safe_purchase_open:
		if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
			handle_ui("safe_purchase_close")
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if state=="raid":
			if event.physical_keycode==KEY_E and overlay.is_empty() and is_instance_valid(current_loot):
				open_container(current_loot)
			if event.physical_keycode==KEY_ESCAPE:
				if overlay.is_empty(): overlay="pause"
				else: overlay=""
				set_capture()
			if event.physical_keycode==KEY_TAB:
				overlay = "" if overlay=="inventory" else "inventory"
				set_capture()
				get_viewport().set_input_as_handled()
			if event.physical_keycode==KEY_M:
				overlay = "" if overlay=="map" else "map"
				set_capture()
		elif state=="menu":
			if event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_8:
				handle_ui("weapon:"+str(event.physical_keycode-KEY_1))
			if event.physical_keycode==KEY_ENTER: start_requested = true
		if state=="raid" and overlay in ["inventory","search"] and event.physical_keycode==KEY_R:
			rotate_item()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and state=="raid" and overlay.is_empty():
		overlay="pause"
		set_capture()

func _process(delta: float) -> void:
	message_left = maxf(0,message_left-delta)
	season_check_left-=delta
	if state=="menu" and season_check_left<=0:
		season_check_left=1.0
		if safe_boxes.refresh_season(): save_profile()
	menu_time += delta
	if state=="menu":
		menu_camera.position = Vector3(136+sin(menu_time*0.055)*9,99,153)
		menu_camera.look_at(Vector3(-2,0,-15))
		showcase_root.rotation.y = -0.55+sin(menu_time*0.28)*0.13
	if start_requested:
		start_requested = false
		session.begin_matchmaking()
	if state=="raid" and overlay=="search": advance_search(delta)
	if state=="raid" and is_instance_valid(player):
		last_interaction_scan-=delta
		if last_interaction_scan<=0:
			last_interaction_scan=0.1
			find_loot()
	if not active_simulation(): return
	if session.running:
		return # The authority advances the shared clock and every player's extraction.
	raid_left = maxf(0,raid_left-delta)
	if raid_left<=0:
		finish_raid(false,"行动超时 · 接应窗口关闭")
		return
	extract_index=-1
	for i in range(2):
		if i==1 and RAID_LENGTH-raid_left<60: continue
		if player.global_position.distance_to(RaidWorld.EXITS[i])<6:
			extract_index=i
	if extract_index>=0:
		extract_progress+=delta
		if extract_progress>=10: finish_raid(true,"成功撤离潮汐港")
	else: extract_progress=0

func active_simulation() -> bool:
	if session.running: return session.is_authority() or state=="raid"
	return state=="raid" and overlay.is_empty()

func accepts_player_input() -> bool:
	return state=="raid" and overlay.is_empty()

func set_capture() -> void:
	if session.context_peer != 0: return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if accepts_player_input() else Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(player): player.queued_shot=false
	if is_instance_valid(player): player.capture_grace=0.18
	session.sync_search_state()

func setup_showcase() -> void:
	showcase_viewport = SubViewport.new()
	showcase_viewport.size = Vector2i(1000,570)
	showcase_viewport.transparent_bg = true
	showcase_viewport.own_world_3d = true
	showcase_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(showcase_viewport)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("b0c4c5")
	environment.ambient_light_energy=0.8
	env.environment=environment
	showcase_viewport.add_child(env)
	var camera := Camera3D.new()
	camera.position=Vector3(1.25,0.65,1.35)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.03
	showcase_viewport.add_child(camera)
	camera.look_at(Vector3(0,0,-0.16))
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-40,-35,0)
	light.light_energy=2
	showcase_viewport.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(20,150,0)
	fill.light_color=Color("84c6d5")
	fill.light_energy=1.4
	showcase_viewport.add_child(fill)
	showcase_root=Node3D.new()
	showcase_viewport.add_child(showcase_root)
	showcase_texture=showcase_viewport.get_texture()
	update_showcase()

func update_showcase() -> void:
	if is_instance_valid(showcase_gun):
		showcase_root.remove_child(showcase_gun)
		showcase_gun.queue_free()
	showcase_gun=Arsenal.build_model(selected_weapon,build_for(selected_weapon))
	showcase_root.add_child(showcase_gun)
	showcase_root.rotation=Vector3(-0.1,-0.55,0.08)

func start_raid(network_start: bool=false) -> void:
	if state!="menu" and state!="matching": return
	# Dedicated servers create a hidden placeholder, not a deploying participant.
	if not (network_start and session.dedicated) and not can_deploy():
		notify("机密行动需要战备值 ¥ "+ui.money(CLASSIFIED_READINESS)+" · 当前 ¥ "+ui.money(loadout_readiness()),4)
		return
	# First deployment after changing modes also needs the matching raid rules.
	if raids>0 or is_instance_valid(player) or world.raid_mode!=raid_mode:
		remove_child(world)
		world.queue_free()
		world=RaidWorld.new()
		world.raid_mode=raid_mode
		add_child(world)
	if is_instance_valid(player):
		remove_child(player)
		player.queue_free()
	player=RaidPlayer.new()
	player.game=self
	player.name="LocalPlayer"
	player.network_id=multiplayer.get_unique_id() if network_start else 1
	player.weapon_index=int(deployment_loadout().weapon)
	player.position=Vector3(-76,0.2,86)
	player.rotation.y=-0.12
	add_child(player)
	apply_loadout_to_player()
	player.camera.make_current()
	for enemy in world.enemies: enemy.target=player
	raid_left=RAID_LENGTH
	kills=0
	shots=0
	extract_progress=0
	extract_index=-1
	current_loot=null
	search_container=null
	inspected_index=-1
	overlay=""
	state="raid"
	set_capture()
	notify("已进入潮汐港 · 朝向容器按 E 搜索，点击物品查看详情",6)

func apply_loadout_to_player() -> void:
	safe_boxes.refresh_season()
	configure_safe_box(player,safe_boxes.equipped)
	player.raid_season=safe_boxes.season
	var carried:=deployment_loadout()
	player.configure_protection(carried)
	var ammo_packs:=int(carried.ammo_packs)
	player.meds=2 if smoke_mode else int(carried.medkits)
	player.reserve=int(player.weapon.reserve)+ammo_packs*120 if smoke_mode else ammo_packs*120

func configure_safe_box(actor: RaidPlayer, id: String) -> void:
	var box:=SafeBoxes.definition(id)
	if box.is_empty(): box=SafeBoxes.definition(SafeBoxes.DEFAULT_ID)
	actor.safe_box_id=str(box.id)
	actor.safe_columns=int(box.columns)
	actor.safe_rows=int(box.rows)

func equip_safe_box(id: String) -> void:
	if state!="menu" or not safe_boxes.equip(id): return
	save_profile()
	notify("已装备 "+safe_box_label(id))

func claim_safe_box(id: String) -> void:
	if state!="menu": return
	if not safe_boxes.claim(id):
		notify("请先完成本赛季保险箱任务")
		return
	save_profile()
	notify("已领取并装备 "+safe_box_label(id)+" · 本赛季有效",4)

func safe_box_label(id: String) -> String:
	var box:=SafeBoxes.definition(id)
	return "%d × %d 保险箱" % [int(box.get("columns",1)),int(box.get("rows",2))]

func apply_verified_safe_purchase(product: String, transaction: String) -> bool:
	# Called after trusted payment verification or verification of a merchant-signed code.
	if not safe_boxes.fulfill_purchase(product,transaction): return false
	if state=="menu": safe_boxes.equip(SafeBoxes.PAID_ID)
	save_profile()
	notify("2 × 4 保险箱永久权限已到账",4)
	return true

func redeem_safe_purchase(code: String) -> bool:
	if state!="menu" or not safe_purchase_open: return false
	safe_purchase_success=false
	var verified: Dictionary=manual_safe_purchase.verify(code,safe_boxes.purchase_id)
	if not verified.ok:
		safe_purchase_message=str(verified.message)
		return false
	if not apply_verified_safe_purchase(verified.product,verified.transaction):
		safe_purchase_message="此激活码已经使用，永久权限已保存在本机档案。"
		safe_purchase_success=safe_boxes.available(SafeBoxes.PAID_ID)
		return false
	safe_purchase_success=true
	safe_purchase_message="激活成功！2 × 4 永久保险箱已装备。"
	return true

func can_deploy() -> bool:
	return raid_mode!="机密" or loadout_readiness()>=CLASSIFIED_READINESS

func deployment_loadout() -> Dictionary:
	# Catalogue previews are not carried equipment until they are unlocked.
	var carried:=loadout.duplicate(true)
	var index:=int(loadout.get("weapon",-1))
	carried.weapon=index if index>=0 and index<Arsenal.all().size() and (smoke_mode or owned_gear.has("weapon:%d" % index)) else -1
	for slot in ["armor","helmet"]:
		var id:=str(loadout.get(slot,""))
		carried[slot]=id if EquipmentData.gear_item(id).get("slot","")==slot and (smoke_mode or owned_gear.has(id)) else ""
	carried.ammo_packs=maxi(int(loadout.get("ammo_packs",0)),0)
	carried.medkits=maxi(int(loadout.get("medkits",0)),0)
	return carried

func loadout_readiness() -> int:
	var total:=0
	var carried:=deployment_loadout()
	var weapon:=WeaponModsData.weapon(int(carried.weapon),build_for(int(carried.weapon)))
	total+=int(weapon.get("value",weapon.get("price",0)))
	for slot in ["armor","helmet"]:
		var item:=EquipmentData.gear_item(str(carried.get(slot,"")))
		total+=int(item.get("value",0))
	total+=int(carried.ammo_packs)*int(EquipmentData.gear_item("ammo_pack").get("value",0))
	total+=int(carried.medkits)*int(EquipmentData.gear_item("medkit").get("value",0))
	return total

func buy_weapon(index: int) -> void:
	var weapon:=Arsenal.get_weapon(index)
	var price:=int(weapon.get("price",0))
	if owned_gear.has("weapon:%d" % index):
		loadout.weapon=index
		selected_weapon=index
		update_showcase()
		notify("已装备 "+str(weapon.name),2)
		save_profile()
		return
	if bank<price:
		notify("余额不足 · 需要 ¥ "+ui.money(price),3)
		return
	bank-=price
	owned_gear["weapon:%d" % index]=true
	loadout.weapon=index
	selected_weapon=index
	update_showcase()
	notify("已采购 "+str(weapon.name)+" · ¥ "+ui.money(price),3)
	save_profile()

func buy_gear(id: String, amount: int=1) -> void:
	if state!="menu" or amount<1 or amount>100: return
	var item:=EquipmentData.gear_item(id)
	if item.is_empty(): return
	if int(item.get("tier",0))==6 and not owned_gear.has(id):
		notify("六级装备仅限极地典藏咖啡兑换，无法用余额购买",4)
		return
	var price:=int(item.get("price",item.get("unit_price",0)))*amount
	if owned_gear.has(id) and id not in ["ammo_pack","medkit"]:
		loadout[str(item.slot)]=id
		notify("已装备 "+str(item.name),2)
		save_profile()
		return
	if bank<price:
		notify("余额不足 · 需要 ¥ "+ui.money(price),3)
		return
	bank-=price
	if id in ["ammo_pack","medkit"]:
		var key: String="ammo_packs" if id=="ammo_pack" else "medkits"
		loadout[key]=int(loadout.get(key,0))+amount
	else:
		owned_gear[id]=true
		loadout[str(item.slot)]=id
	notify("已采购并装备 "+str(item.name)+" · ¥ "+ui.money(price),3)
	save_profile()

func exchange_count() -> int:
	var count:=0
	for item in stash:
		if item.get("id","")==EquipmentData.EXCHANGE_ITEM and not item.get("settled",false): count+=1
	return count

func redeem_gear(id: String) -> bool:
	if state!="menu": return false
	var item:=EquipmentData.gear_item(id)
	if item.is_empty() or int(item.get("tier",0))!=6 or owned_gear.has(id): return false
	for i in range(stash.size()):
		if stash[i].get("id","")==EquipmentData.EXCHANGE_ITEM and not stash[i].get("settled",false):
			stash.remove_at(i)
			owned_gear[id]=true
			loadout[str(item.slot)]=id
			inspected_index=-1
			save_profile()
			notify("已消耗 1 罐极地典藏咖啡，解锁并装备 "+str(item.name),4)
			return true
	notify("需要带回 1 罐极地典藏咖啡 · 指定容器概率 0.3%",4)
	return false

func select_raid_mode(mode: String) -> void:
	raid_mode=mode
	if mode=="机密" and loadout_readiness()<CLASSIFIED_READINESS:
		notify("机密行动需要战备值 ¥ "+ui.money(CLASSIFIED_READINESS)+" · 当前 ¥ "+ui.money(loadout_readiness()),4)
	else:
		notify(("机密" if mode=="机密" else "普通")+"行动已选择",2)

func find_loot() -> void:
	current_loot=null
	var nearest:=3.0
	for chest in world.loot:
		if chest.get_meta("searched"): continue
		var distance:=player.global_position.distance_to(chest.global_position)
		if distance<nearest:
			var toward: Vector3=(chest.global_position-player.camera.global_position).normalized()
			if (-player.camera.global_basis.z).dot(toward)<0.48: continue
			var ray:=PhysicsRayQueryParameters3D.create(player.camera.global_position,chest.global_position,1)
			var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty() and not chest.is_ancestor_of(hit.collider): continue
			current_loot=chest
			nearest=distance

func build_for(index: int) -> Dictionary:
	return WeaponModsData.sanitize(index,weapon_builds.get(str(index),{}))

func equip_mod(id: String) -> void:
	if state!="menu": return
	var build:=build_for(selected_weapon)
	if id=="none":
		build.erase(mod_slot)
	else:
		var mod:=WeaponModsData.get_mod(id)
		if mod.is_empty() or mod.slot!=mod_slot or selected_weapon not in mod.compatible: return
		if not owned_gear.has("weapon:%d" % selected_weapon):
			notify("请先在装备采购中购买这把武器")
			return
		if not owned_gear.has("mod:"+id):
			if bank<int(mod.price):
				notify("余额不足 · 需要 ¥ "+ui.money(int(mod.price)))
				return
			bank-=int(mod.price)
			owned_gear["mod:"+id]=true
		build[mod_slot]=id
	weapon_builds[str(selected_weapon)]=build
	update_showcase()
	save_profile()
	notify("改装方案已保存 · "+str(Arsenal.get_weapon(selected_weapon).name))

func open_container(chest: Node3D) -> void:
	if state!="raid" or not is_instance_valid(chest) or chest not in world.loot: return
	if player.global_position.distance_to(chest.global_position)>3.0: return
	if session.running and not session.applying_action:
		session.open_search(world.loot.find(chest))
		return
	search_container=chest
	search_paused=false
	inspected_source=""
	inspected_index=-1
	overlay="search"
	set_capture()

func advance_search(delta: float) -> void:
	if session.running: return # All searches share the authority's container clock.
	if not is_instance_valid(search_container):
		overlay=""
		set_capture()
		return
	if search_paused: return
	var contents: Array=search_container.get_meta("items")
	var revealed:=int(search_container.get_meta("revealed"))
	if revealed>=contents.size(): return
	var kind: String=search_container.get_meta("kind")
	var elapsed:=float(search_container.get_meta("search_elapsed"))+delta
	var duration:=float(ItemsData.CONTAINERS[kind].time)
	while elapsed>=duration and revealed<contents.size():
		elapsed-=duration
		revealed+=1
		audio.play_sound("loot",-24)
	search_container.set_meta("revealed",revealed)
	search_container.set_meta("search_elapsed",elapsed if revealed<contents.size() else 0.0)

func mark_container() -> void:
	if not is_instance_valid(search_container): return
	var empty: bool=search_container.get_meta("items").is_empty()
	search_container.set_meta("searched",empty)
	if empty: search_container.get_node("Indicator").material_override=world.mats.dark

func take_loot(index: int) -> bool:
	if session.running and not session.applying_action: return session.item_action("take",index)
	if state!="raid" or overlay!="search" or not is_instance_valid(search_container): return false
	var contents: Array=search_container.get_meta("items")
	var revealed:=int(search_container.get_meta("revealed"))
	if index<0 or index>=revealed or index>=contents.size(): return false
	var item: Dictionary=contents[index].duplicate(true)
	if not player.can_store(item):
		notify("背包空间或负重不足 · 可整理、旋转或移入安全箱")
		return false
	player.inventory.append(item)
	contents.remove_at(index)
	search_container.set_meta("revealed",revealed-1)
	mark_container()
	inspected_index=-1
	if player.is_local: audio.play_sound("loot",-16)
	return true

func take_all_loot() -> void:
	if session.running and not session.applying_action:
		session.item_action("take_all")
		return
	if not is_instance_valid(search_container): return
	var index:=0
	while index<int(search_container.get_meta("revealed")):
		if not take_loot(index): index+=1

func inspect_item(source: String, index: int) -> void:
	inspected_source=source
	inspected_index=index

func inspected_items() -> Array:
	if inspected_source=="bag" and is_instance_valid(player): return player.inventory
	if inspected_source=="safe" and is_instance_valid(player): return player.safe_inventory
	if inspected_source=="loot" and is_instance_valid(search_container): return search_container.get_meta("items")
	if inspected_source=="stash": return stash
	return []

func selected_item() -> Dictionary:
	var items:=inspected_items()
	if inspected_index<0 or inspected_index>=items.size(): return {}
	if inspected_source=="loot" and inspected_index>=int(search_container.get_meta("revealed")): return {}
	return items[inspected_index]

func rotate_item() -> void:
	if session.running and not session.applying_action:
		session.item_action("rotate")
		return
	var item:=selected_item()
	if item.is_empty() or inspected_source not in ["bag","safe"]: return
	var before:=ItemsData.grid_size(item)
	item.w=before.y
	item.h=before.x
	var items:=inspected_items()
	var columns:=player.safe_columns if inspected_source=="safe" else player.bag_columns
	var rows:=player.safe_rows if inspected_source=="safe" else player.bag_rows
	if ItemsData.pack(items,columns,rows).size()!=items.size():
		item.w=before.x
		item.h=before.y
		notify("当前空间无法旋转该物品")

func move_secure() -> void:
	if state!="raid": return
	if session.running and not session.applying_action:
		session.item_action("secure")
		return
	var item:=selected_item()
	if item.is_empty() or inspected_source not in ["bag","safe"]: return
	var destination: Array=player.safe_inventory if inspected_source=="bag" else player.inventory
	var proposed:=destination.duplicate()
	proposed.append(item)
	var columns:=player.safe_columns if inspected_source=="bag" else player.bag_columns
	var rows:=player.safe_rows if inspected_source=="bag" else player.bag_rows
	if ItemsData.pack(proposed,columns,rows).size()!=proposed.size():
		notify("目标容器格子不足")
		return
	destination.append(item)
	inspected_items().remove_at(inspected_index)
	inspected_index=-1

func use_item() -> void:
	if session.running and not session.applying_action:
		session.item_action("use_item")
		return
	var item:=selected_item()
	if state!="raid" or item.is_empty() or inspected_source not in ["bag","safe"]: return
	if item.has("heal"):
		if player.health>=100:
			notify("生命已满，无需使用")
			return
		player.health=minf(100,player.health+float(item.heal))
		player.heal_left=0
	elif item.has("ammo"):
		player.reserve+=int(item.ammo)
	else: return
	inspected_items().remove_at(inspected_index)
	inspected_index=-1
	notify("已使用 "+str(item.name))

func sort_bag() -> void:
	if session.running and not session.applying_action:
		session.item_action("sort")
		return
	if not is_instance_valid(player): return
	var original:=player.inventory.duplicate()
	player.inventory.sort_custom(func(a: Dictionary,b: Dictionary): return ItemsData.grid_size(a).x*ItemsData.grid_size(a).y>ItemsData.grid_size(b).x*ItemsData.grid_size(b).y)
	if ItemsData.pack(player.inventory,player.bag_columns,player.bag_rows).size()!=player.inventory.size(): player.inventory=original
	inspected_index=-1

func sell_item() -> void:
	if state!="menu" or inspected_source!="stash": return
	var item:=selected_item()
	if item.is_empty(): return
	if item.get("settled",false):
		notify("该物资已在旧版自动结算，仅保留回收档案")
		return
	bank+=int(item.value)
	stash.remove_at(inspected_index)
	inspected_index=-1
	save_profile()
	notify("已出售 "+str(item.name)+" · ¥ "+ui.money(int(item.value)))

func unlock_mods(cargo: Array) -> void:
	for item in cargo:
		if item.has("mod") and not WeaponModsData.get_mod(str(item.mod)).is_empty(): owned_gear["mod:"+str(item.mod)]=true

func notify(text: String, duration: float=3.0) -> void:
	if session.context_peer != 0: return
	message=text
	message_left=duration

func finish_raid(success: bool, reason: String) -> void:
	if state!="raid": return
	if session.running and not session.applying_result:
		session.request_finish(success,reason)
		return
	result_success=success
	result_reason=reason
	state="result"
	overlay=""
	raids+=1
	var secured: Array=player.inventory.duplicate(true) if success else []
	secured.append_array(player.safe_inventory.duplicate(true))
	stash.append_array(secured)
	unlock_mods(secured)
	safe_boxes.record_raid(success,secured,kills,player.raid_season)
	if success:
		escaped+=1
		audio.play_sound("extract",-13)
	save_profile()
	set_capture()

func handle_ui(action: String) -> void:
	if safe_purchase_open:
		match action:
			"safe_purchase_close":
				safe_purchase_open=false
				ui.purchase_code_edit.release_focus()
			"safe_copy_id":
				DisplayServer.clipboard_set(safe_boxes.purchase_id)
				safe_purchase_message="购买编号已复制，请连同付款凭证通过微信发给收款人。"
				safe_purchase_success=true
			"safe_redeem": redeem_safe_purchase(ui.purchase_code_edit.text)
		return
	if action.begins_with("safe_equip:"):
		equip_safe_box(action.get_slice(":",1))
		return
	if action.begins_with("safe_claim:"):
		claim_safe_box(action.get_slice(":",1))
		return
	if action=="safe_purchase" and state=="menu":
		manual_safe_purchase.reload_config()
		safe_purchase_open=true
		start_requested=false
		safe_purchase_message=""
		safe_purchase_success=false
		save_profile() # Persist the buyer ID before anyone can pay or request a code.
		ui.purchase_code_edit.clear()
		ui.purchase_code_edit.call_deferred("grab_focus")
		return
	if action=="cancel_match":
		session.cancel()
		return
	if action=="network_settings":
		session.show_settings()
		return
	if session.running and action=="discard":
		session.item_action("discard")
		return
	if action.begins_with("weapon:"):
		selected_weapon=int(action.get_slice(":",1))
		if owned_gear.has("weapon:%d" % selected_weapon):
			loadout.weapon=selected_weapon
			save_profile()
		update_showcase()
	elif action.begins_with("tab:"):
		menu_tab=action.get_slice(":",1)
		inspected_index=-1
	elif action.begins_with("modslot:"):
		mod_slot=action.get_slice(":",1)
	elif action.begins_with("mod:"):
		equip_mod(action.get_slice(":",1))
	elif action.begins_with("inspect:"):
		inspect_item(action.get_slice(":",1),int(action.get_slice(":",2)))
	elif action.begins_with("take:"): take_loot(int(action.get_slice(":",1)))
	elif action=="take_all": take_all_loot()
	elif action=="search_toggle":
		search_paused=not search_paused
		session.sync_search_state()
	elif action=="sort_bag": sort_bag()
	elif action=="rotate": rotate_item()
	elif action=="secure": move_secure()
	elif action=="use_item": use_item()
	elif action=="sell": sell_item()
	elif action=="discard" and state=="raid" and inspected_source in ["bag","safe"]:
		if not selected_item().is_empty():
			inspected_items().remove_at(inspected_index)
			inspected_index=-1
	elif action.begins_with("stashfilter:"):
		stash_filter=action.get_slice(":",1)
		stash_page=0
		inspected_index=-1
	elif action.begins_with("stashpage:"):
		stash_page=maxi(0,stash_page+int(action.get_slice(":",1)))
		inspected_index=-1
	elif action.begins_with("raidmode:"):
		select_raid_mode(action.get_slice(":",1))
	elif action.begins_with("buy_weapon:"):
		buy_weapon(int(action.get_slice(":",1)))
	elif action.begins_with("market:"):
		market_slot=action.get_slice(":",1)
		if market_slot in ["armor","helmet"]: selected_gear=EquipmentData.gear_for_slot(market_slot)[0].id
	elif action.begins_with("gearselect:"):
		selected_gear=action.get_slice(":",1)
	elif action.begins_with("redeem:"):
		redeem_gear(action.get_slice(":",1))
	elif action.begins_with("buy_gear:"):
		buy_gear(action.get_slice(":",1))
	elif action.begins_with("buy_consumable:"):
		buy_gear(action.get_slice(":",1))
	elif action=="deploy": start_requested=true
	elif action=="resume":
		overlay=""
		set_capture()
	elif action=="abort": finish_raid(false,"主动结束行动")
	elif action=="return":
		session.leave()
		state="menu"
		menu_tab="deploy"
		menu_camera.make_current()
		set_capture()
	elif action.begins_with("drop:") and state=="raid":
		var index:=int(action.get_slice(":",1))
		if index>=0 and index<player.inventory.size():
			player.inventory.remove_at(index)
			notify("已丢弃物品")

func load_profile() -> void:
	if not FileAccess.file_exists(profile_path): return
	var data=JSON.parse_string(FileAccess.get_file_as_string(profile_path))
	if data is Dictionary:
		bank=int(data.get("bank",25000))
		stash=data.get("stash",[])
		raids=int(data.get("raids",0))
		escaped=int(data.get("escaped",0))
		owned_gear=data.get("owned_gear",{})
		loadout=data.get("loadout",loadout)
		safe_boxes.restore(data.get("safe_boxes",{}) if data.get("safe_boxes",{}) is Dictionary else {})
		raid_mode=str(data.get("raid_mode","普通"))
		selected_weapon=clampi(int(loadout.get("weapon",0)),0,7)
		weapon_builds.clear()
		var saved_builds=data.get("weapon_builds",{})
		if saved_builds is Dictionary:
			for key in saved_builds:
				if saved_builds[key] is Dictionary:
					var clean:=WeaponModsData.sanitize(int(key),saved_builds[key])
					for slot in clean.keys():
						if not owned_gear.has("mod:"+str(clean[slot])): clean.erase(slot)
					weapon_builds[str(clampi(int(key),0,7))]=clean
		migrate_equipment()
		# Legacy profiles treated stash as an already-paid archive.
		# Mark those entries so the new sale action cannot pay them twice.
		if int(data.get("profile_version",1))<2:
			for item in stash: item["settled"]=true
		if int(data.get("profile_version",1))<3: save_profile()
func migrate_equipment() -> void:
	var refund:=0
	for id in EquipmentData.LEGACY_REFUNDS:
		if owned_gear.has(id):
			refund+=int(EquipmentData.LEGACY_REFUNDS[id])
			owned_gear.erase(id)
	bank+=refund
	loadout.erase("backpack")
	loadout.erase("rig")
	for slot in ["armor","helmet"]:
		var id:=str(loadout.get(slot,""))
		if not id.is_empty() and EquipmentData.gear_item(id).get("slot","")!=slot:
			loadout[slot]=slot+"_1"
	if refund>0:
		message="旧防护与携行装备已移除，采购金额全额返还 ¥ %d" % refund
		message_left=8

func _save_loadout() -> Dictionary:
	return {"weapon":int(loadout.get("weapon",0)),"armor":str(loadout.get("armor","armor_1")),"helmet":str(loadout.get("helmet","helmet_1")),"ammo_packs":int(loadout.get("ammo_packs",0)),"medkits":int(loadout.get("medkits",0))}

func save_profile() -> void:
	var file:=FileAccess.open(profile_path,FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"bank":bank,"stash":stash,"raids":raids,"escaped":escaped,"owned_gear":owned_gear,"loadout":_save_loadout(),"raid_mode":raid_mode,"weapon_builds":weapon_builds,"safe_boxes":safe_boxes.serialize(),"profile_version":3}))
	else:
		storage_warning="本次存档失败，请检查用户目录权限。"

func tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var mesh:=ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var instance:=MeshInstance3D.new()
	instance.mesh=mesh
	var mat:=Arsenal.material(color)
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	instance.material_override=mat
	add_child(instance)
	get_tree().create_timer(0.055).timeout.connect(instance.queue_free)

func impact(pos: Vector3, normal: Vector3) -> void:
	var mesh:=Arsenal.box(self,Vector3(0.045,0.045,0.045),pos+normal*0.015,world.mats.ivory)
	get_tree().create_timer(1.2).timeout.connect(mesh.queue_free)

func enemy_shot(from: Vector3, to: Vector3) -> void:
	if session.running:
		if session.is_authority(): session.shot_event.rpc(0,from,to)
		return
	tracer(from,to+Vector3(randf_range(-0.6,0.6),randf_range(-0.3,0.3),0),Color("e3a577"))
	if is_instance_valid(player): player.hear_sound(from,"shot",42.0)
	if session.running and session.is_authority():
		session.guard_shot.rpc(from,to)
		for actor in session.actors.values():
			for child in actor.get_children():
				if child is Session.BotBrain: child.hear_noise(from,42.0)

# Integration checks run in the engine, against the real physics world.
func run_smoke_test() -> void:
	await get_tree().physics_frame
	preload("res://tests/equipment_checks.gd").base_checks(self)
	assert(Arsenal.all().size()==8,"Eight weapon profiles must load")
	assert(world.loot.size()==48,"Map must contain 48 searchable containers")
	assert(world.enemies.size()==14,"Map must contain 14 patrols")
	var kinds: Dictionary={}
	for chest in world.loot:
		kinds[chest.get_meta("kind")]=true
		var contents: Array=chest.get_meta("items")
		assert(contents.size()>=2 and contents.size()<=4)
		assert(Items.pack(contents,6,4).size()==contents.size(),"All rolled contents must fit their container")
	assert(kinds.size()==8,"All eight container types must appear")
	for i in range(8):
		for slot in WeaponMods.SLOTS:
			for mod in WeaponMods.options(i,slot):
				var build: Dictionary={slot:mod.id}
				var profile:=WeaponMods.weapon(i,build)
				assert(profile.magazine>0 and profile.reload>0 and profile.weight>0)
				var model:=Arsenal.build_model(i,build)
				model.free()
	assert(WeaponMods.sanitize(4,{"grip":"grip_vertical","optic":"scope_8x"}).is_empty(),"Incompatible attachments must be rejected")
	var base:=Arsenal.get_weapon(0).duplicate(true)
	var modified:=WeaponMods.weapon(0,{"magazine":"mag_extended","muzzle":"suppressor","optic":"scope_4x"})
	assert(modified.magazine==45 and modified.reload>base.reload and modified.noise_radius==20 and modified.aim_fov==26)
	assert(Arsenal.get_weapon(0)==base,"Modifications must not mutate base weapon profiles")
	bank=100000
	buy_weapon(0)
	var purchase_bank:=bank
	buy_weapon(0)
	assert(bank==purchase_bank,"Owned weapons must not charge twice")
	mod_slot="muzzle"
	equip_mod("suppressor")
	var mod_bank:=bank
	equip_mod("none")
	equip_mod("suppressor")
	assert(bank==mod_bank,"Owned attachments must reinstall without charge")
	mod_slot="magazine"
	equip_mod("mag_extended")
	bank=0
	mod_slot="optic"
	equip_mod("scope_8x")
	assert(not build_for(0).has("optic"),"Incompatible purchases must leave the build unchanged")
	equip_mod("scope_4x")
	assert(not build_for(0).has("optic"),"Insufficient balance must not install an attachment")
	bank=mod_bank
	loadout.medkits=2
	save_profile()
	var saved_builds:=weapon_builds.duplicate(true)
	weapon_builds={}
	load_profile()
	assert(weapon_builds==saved_builds,"Mod loadouts and ownership must round-trip through storage")
	start_raid()
	await get_tree().physics_frame
	await get_tree().physics_frame
	preload("res://tests/equipment_checks.gd").field_checks(self)
	assert(player.ammo==45 and player.weapon.noise_radius==20,"The real player must receive the modified weapon")
	weapon_builds={}
	for i in range(8):
		player.equip(i)
		var loaded_ammo:=player.ammo
		player.fire()
		assert(player.ammo==loaded_ammo-1,"Every weapon must fire")
	player.equip(0)
	assert(world.path_between(Vector3(-76,0,86),RaidWorld.EXITS[0]).size()>2)
	assert(world.path_between(Vector3(-76,0,86),RaidWorld.EXITS[1]).size()>2)
	player.fire()
	player.reload_weapon()
	player.reload_left=0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.ammo==30 and player.reserve==149,"Reload must transfer reserve ammo")
	var chest: Node3D=world.loot[0]
	chest.set_meta("items",[Items.get_item("bandage"),Items.get_item("mod_compensator"),Items.get_item("drive"),Items.get_item("ammo")])
	player.position=chest.position+Vector3(0,-0.5,2)
	player.rotation.y=0
	await get_tree().physics_frame
	find_loot()
	assert(current_loot==chest,"Nearby visible containers must be interactable")
	open_container(chest)
	assert(overlay=="search" and not take_loot(0),"Unknown items cannot be taken")
	var time_before:=raid_left
	_process(0.4)
	assert(int(chest.get_meta("revealed"))==0 and raid_left==time_before,"Search UI freezes the raid clock but reveals items over time")
	search_paused=true
	advance_search(9.0)
	assert(int(chest.get_meta("revealed"))==0,"Pausing search must stop discovery")
	search_paused=false
	advance_search(0.5)
	assert(int(chest.get_meta("revealed"))==1)
	handle_ui("resume")
	open_container(chest)
	assert(int(chest.get_meta("revealed"))==1,"Reopening a container must preserve discovery")
	assert(take_loot(0) and player.inventory.size()==1)
	assert(not take_loot(0),"The next unknown item remains unavailable")
	advance_search(10.0)
	var contents_before:=int(chest.get_meta("items").size())
	player.capacity=0.01
	assert(not take_loot(0) and chest.get_meta("items").size()==contents_before,"Weight rejection must be atomic")
	player.capacity=20
	for i in range(23): player.inventory.append(Items.get_item("bolts"))
	assert(not take_loot(0) and chest.get_meta("items").size()==contents_before,"Grid-full rejection must preserve both inventories")
	player.inventory.resize(1)
	inspect_item("bag",0)
	move_secure()
	assert(player.inventory.is_empty() and player.safe_inventory.size()==1,"Safe box transfer must move the item once")
	inspect_item("safe",0)
	player.health=70
	use_item()
	assert(player.health==90 and player.safe_inventory.is_empty(),"Looted medical items must heal and consume once")
	take_all_loot()
	assert(chest.get_meta("items").is_empty() and chest.get_meta("searched"),"Take-all must empty revealed contents")
	assert(player.inventory.size()==3)
	inspect_item("bag",0)
	rotate_item() # A 2×1 attachment must be rotated to fit the starter 1×2 safe.
	move_secure()
	assert(player.safe_inventory.size()==1)
	inspect_item("bag",0)
	rotate_item()
	assert(Items.grid_size(player.inventory[0])==Vector2i(1,2),"Rotation must change inventory footprint")
	inspect_item("bag",1)
	var ammo_before:=player.reserve
	use_item()
	assert(player.reserve==ammo_before+30,"Looted ammunition must refill the current weapon")
	handle_ui("resume")
	var victim=world.enemies[0]
	assert(victim.take_hit(1000,victim.global_position+Vector3.UP*1.7))
	assert(victim.dead and victim.collision_layer==0)
	player.take_damage(20)
	assert(player.health<100 and player.armor<70)
	player.heal()
	player.heal_left=0.01
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert(player.health==100 and player.meds==1)
	overlay="pause"
	time_before=raid_left
	_process(4.0)
	assert(raid_left==time_before)
	overlay=""
	player.position=RaidWorld.EXITS[0]
	_process(2.0)
	assert(extract_progress>=2)
	player.position=Vector3(-76,0,86)
	_process(0.1)
	assert(extract_progress==0)
	var bank_before:=bank
	var cargo_count:=player.inventory.size()+player.safe_inventory.size()
	player.position=RaidWorld.EXITS[0]
	extract_progress=9.95
	_process(0.1)
	assert(state=="result" and result_success)
	assert(bank==bank_before and stash.size()==cargo_count,"Extraction must store cargo without paying twice")
	assert(owned_gear.has("mod:compensator"),"Extracted attachments must unlock base modification")
	handle_ui("return")
	inspect_item("stash",0)
	var sale_value:=int(selected_item().value)
	sell_item()
	assert(bank==bank_before+sale_value and stash.size()==cargo_count-1,"Sale must remove one item and pay once")
	sell_item()
	assert(bank==bank_before+sale_value,"Repeated sale must not duplicate payment")
	var saved_bank:=bank
	bank=0
	load_profile()
	assert(bank==saved_bank)
	start_raid()
	await get_tree().physics_frame
	assert(player.inventory.is_empty() and player.safe_inventory.is_empty() and not world.loot[0].get_meta("searched"))
	assert(not world.enemies[0].dead)
	player.inventory.append(Items.get_item("terminal"))
	player.safe_inventory.append(Items.get_item("gold"))
	var stash_before:=stash.size()
	player.take_damage(1000)
	assert(state=="result" and not result_success)
	assert(stash.size()==stash_before+1 and stash.back().id=="gold","Only safe-box cargo survives a failed raid")
	assert(bank==saved_bank)
	DirAccess.remove_absolute(profile_path)
	print("SMOKE PASS: 20 armor/helmet profiles, tier-6 barter, migration, hearing, head/body damage, seeded rare loot, 8 weapons, 13 mods, 48 containers / 8 types, themed rolls, compatibility, ownership, save/load, live mod stats, routes, shooting, reload, search/reopen/pause, unknown loot, atomic transfer, grid/weight, safe box, rotation, consumables, extraction, sale, retry, death")
	await get_tree().process_frame
	get_tree().quit()

func capture_preview() -> void:
	# Use the renderer and an isolated profile; never write to the player's save.
	bank=25000
	raids=0
	escaped=0
	stash=[]
	for slot in ["armor","helmet"]: owned_gear[str(loadout[slot])]=true
	owned_gear["weapon:0"]=true
	loadout.ammo_packs=1
	loadout.medkits=2
	await capture_frame("01-deployment")
	menu_tab="market"
	market_slot="armor"
	selected_gear="armor_3_durable"
	await capture_frame("15-armor-catalogue")
	market_slot="helmet"
	selected_gear="helmet_5_hearing"
	await capture_frame("16-helmet-catalogue")
	market_slot="armor"
	selected_gear="armor_6_durable"
	await capture_frame("17-tier-six-locked")
	stash.append(ItemsData.get_item("polar_coffee"))
	await capture_frame("18-tier-six-barter")
	stash.clear()
	market_slot="weapon"
	await capture_frame("19-weapon-procurement")
	market_slot="supply"
	await capture_frame("20-supply-procurement")
	menu_tab="armory"
	selected_weapon=0
	weapon_builds["0"]={"optic":"scope_4x","muzzle":"suppressor","grip":"grip_vertical","magazine":"mag_extended","stock":"stock_stable","barrel":"barrel_long"}
	for id in weapon_builds["0"].values(): owned_gear["mod:"+str(id)]=true
	update_showcase()
	await capture_frame("02-armory")
	selected_weapon=7
	update_showcase()
	await capture_frame("03-m24")
	menu_tab="deploy"
	selected_weapon=0
	start_raid()
	await get_tree().create_timer(0.3).timeout
	player.rotation.y=-0.12
	player.pitch=0
	await capture_frame("04-in-raid")
	overlay="map"
	set_capture()
	await capture_frame("05-tactical-map")
	for id in ["cpu","circuit","medkit_field","bolts","water","drive","ammo","mod_red_dot"]: player.inventory.append(Items.get_item(id))
	var preview_gold:=Items.get_item("gold")
	preview_gold.w=1
	preview_gold.h=2
	player.safe_inventory.append(preview_gold)
	overlay="inventory"
	inspected_index=-1
	message_left=0
	await capture_frame("06-inventory")
	inspect_item("bag",1)
	await capture_frame("10-item-details")
	var chest: Node3D=world.loot[0]
	chest.set_meta("items",[Items.get_item("mod_compensator"),Items.get_item("ammo_large"),Items.get_item("terminal"),Items.get_item("ammo")])
	chest.set_meta("revealed",2)
	player.position=chest.position+Vector3(0,0,2)
	open_container(chest)
	search_paused=true
	await capture_frame("11-container-search")
	inspect_item("loot",0)
	await capture_frame("12-search-inspector")
	overlay="pause"
	await capture_frame("07-pause")
	state="result"
	result_success=true
	result_reason="成功撤离潮汐港"
	kills=4
	shots=87
	raid_left=393
	await capture_frame("08-extracted")
	state="menu"
	menu_tab="stash"
	stash=player.inventory.duplicate(true)
	stash.append_array(player.safe_inventory.duplicate(true))
	inspect_item("stash",0)
	await capture_frame("13-stash")
	menu_tab="guide"
	await capture_frame("09-guide")
	print("PREVIEW PASS: rendered armor, helmets, tier-six exchange, weapons, supplies, deployment, workbench, M24, raid, map, grid inventory, inspector, container search, pause, extraction, stash and guide")
	get_tree().quit()

func capture_frame(filename: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var screenshot:=get_viewport().get_texture().get_image()
	screenshot.save_png("res://docs/screenshots/"+filename+".png")
