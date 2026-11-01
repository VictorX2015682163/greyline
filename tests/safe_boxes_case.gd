extends SceneTree

const Boxes = preload("res://scripts/safe_boxes.gd")
const Items = preload("res://scripts/items.gd")
var game
var render := false

func _initialize() -> void:
	render="--capture-safes" in OS.get_cmdline_user_args()
	call_deferred("run")

func run() -> void:
	var boxes=Boxes.new()
	boxes.restore({})
	assert(boxes.equipped==Boxes.DEFAULT_ID and boxes.available(Boxes.DEFAULT_ID))
	for id in ["safe_2x2","safe_2x4","safe_3x3"]:
		assert(not boxes.available(id) and not boxes.equip(id),"Locked boxes cannot be equipped")
	assert(not boxes.claim("safe_2x2"),"Tasks must be completed before claiming")
	boxes.record_raid(false,[Items.get_item("gold")],2,boxes.season)
	assert(boxes.progress.extracts==0 and boxes.progress.value==0 and boxes.progress.kills==2)
	for i in range(3): boxes.record_raid(true,[Items.get_item("cpu")],2,boxes.season)
	assert(boxes.claim("safe_2x2") and not boxes.claim("safe_2x2"))
	assert(boxes.equipped=="safe_2x2" and not boxes.available("safe_3x3"))
	for i in range(7): boxes.record_raid(true,[Items.get_item("gold")],2,boxes.season)
	assert(boxes.claim("safe_3x3"))
	assert(not boxes.fulfill_purchase("wrong_product","test-receipt"))
	assert(not boxes.fulfill_purchase(Boxes.PRODUCT_ID,""))
	assert(boxes.fulfill_purchase(Boxes.PRODUCT_ID,"test-receipt"))
	assert(not boxes.fulfill_purchase(Boxes.PRODUCT_ID,"test-receipt"))
	var saved: Dictionary=boxes.serialize()
	var restored=Boxes.new()
	restored.restore(JSON.parse_string(JSON.stringify(saved)))
	assert(restored.available("safe_3x3") and restored.available("safe_2x4"))
	assert(restored.progress==boxes.progress and restored.equipped=="safe_3x3")
	saved.season="2000-S1"
	restored.restore(saved)
	assert(restored.equipped==Boxes.DEFAULT_ID and restored.progress.extracts==0)
	assert(not restored.available("safe_2x2") and not restored.available("safe_3x3"))
	assert(restored.available("safe_2x4"),"Permanent purchases survive season rollover")
	restored.record_raid(true,[Items.get_item("gold")],20,"2000-S1")
	assert(restored.progress.kills==0 and restored.progress.value==0,"Old raids cannot advance the next season")
	saved.equipped="safe_2x4"
	restored.restore(saved)
	assert(restored.equipped=="safe_2x4")
	assert(Boxes.PRICE_FEN==1000)
	game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://safe_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	await process_frame
	var bank_before: int=game.bank
	game.handle_ui("safe_purchase")
	assert(game.safe_purchase_open and not game.safe_boxes.available("safe_2x4"))
	game.handle_ui("safe_purchase_close")
	game.safe_boxes=boxes
	assert(game.apply_verified_safe_purchase(Boxes.PRODUCT_ID,"test-adapter-receipt"))
	assert(not game.apply_verified_safe_purchase(Boxes.PRODUCT_ID,"test-adapter-receipt"))
	assert(game.bank==bank_before,"RMB products cannot spend in-game currency")
	game.safe_boxes=Boxes.new()
	game.load_profile()
	assert(game.safe_boxes.equipped=="safe_2x4" and game.safe_boxes.available("safe_3x3"))
	game.safe_boxes.equip(Boxes.DEFAULT_ID)
	game.start_raid()
	await physics_frame
	game.overlay="inventory"
	game.set_capture()
	var actor: RaidPlayer=game.player
	assert(actor.safe_columns==1 and actor.safe_rows==2)
	actor.inventory=[Items.get_item("pliers"),Items.get_item("bolts")]
	game.inspect_item("bag",0)
	game.move_secure()
	assert(actor.safe_inventory.size()==1 and actor.inventory.size()==1,"A two-cell item fits the connected starter box")
	game.inspect_item("bag",0)
	game.move_secure()
	assert(actor.safe_inventory.size()==1 and actor.inventory.size()==1,"Overflow must preserve both inventories")
	game.inspect_item("safe",0)
	game.rotate_item()
	assert(Items.grid_size(actor.safe_inventory[0])==Vector2i(1,2),"Invalid rotation must roll back")
	game.configure_safe_box(actor,"safe_2x2")
	actor.safe_inventory=[Items.get_item("cpu"),Items.get_item("bolts")]
	actor.inventory=[Items.get_item("pliers")]
	game.inspect_item("bag",0)
	game.move_secure()
	assert(actor.safe_inventory.size()==3 and actor.inventory.is_empty(),"Connected space must fit two singles and a vertical two-cell item regardless of insertion order")
	var packed: Array=Items.pack(actor.safe_inventory,2,2)
	assert(packed.size()==3)
	var occupied: Dictionary={}
	for i in range(actor.safe_inventory.size()):
		var extent:=Items.grid_size(actor.safe_inventory[i])
		for y in range(extent.y):
			for x in range(extent.x):
				var cell: Vector2i=packed[i]+Vector2i(x,y)
				assert(cell.x>=0 and cell.x<2 and cell.y>=0 and cell.y<2 and not occupied.has(cell))
				occupied[cell]=true
	assert(occupied.size()==4,"Automatic arrangement must preserve item order and occupy every cell without overlap")
	for box in Boxes.CATALOGUE:
		game.configure_safe_box(actor,box.id)
		actor.safe_inventory=[]
		var cargo:=Items.get_item("bolts")
		cargo.w=int(box.columns)
		cargo.h=int(box.rows)
		actor.inventory=[cargo,Items.get_item("tape")]
		game.inspect_item("bag",0)
		game.move_secure()
		assert(actor.safe_inventory.size()==1 and actor.inventory.size()==1,"One item can span every connected cell")
		game.inspect_item("bag",0)
		game.move_secure()
		assert(actor.safe_inventory.size()==1 and actor.inventory.size()==1)
		game.inspect_item("safe",0)
		game.move_secure()
		assert(actor.safe_inventory.is_empty() and actor.inventory.size()==2)
	game.configure_safe_box(actor,Boxes.DEFAULT_ID)
	actor.inventory=[Items.get_item("terminal")]
	actor.safe_inventory=[Items.get_item("cpu")]
	var stash_before: int=game.stash.size()
	var progress_before: Dictionary=game.safe_boxes.progress.duplicate()
	game.kills=2
	game.finish_raid(false,"保险箱测试")
	game.finish_raid(false,"重复结算")
	assert(game.stash.size()==stash_before+1 and game.stash.back().id=="cpu")
	assert(game.safe_boxes.progress.kills==progress_before.kills+2)
	assert(game.safe_boxes.progress.extracts==progress_before.extracts)
	game.handle_ui("return")
	game.start_raid()
	await physics_frame
	game.overlay="inventory"
	game.player.safe_inventory=[Items.get_item("cpu")]
	game.kills=1
	game.finish_raid(true,"任务结算测试")
	assert(game.safe_boxes.progress.extracts==progress_before.extracts+1)
	assert(game.safe_boxes.progress.value==progress_before.value+12500)
	game.handle_ui("return")
	# Ignore forged box IDs unless the advertised local profile owns the entitlement.
	game.loadout.ammo_packs=1
	game.loadout.medkits=1
	var profile: Dictionary=game.session.local_profile()
	profile.safe_box_id="safe_3x3"
	profile.safe_boxes={}
	assert(game.session.sanitize_profile(profile).safe_box_id==Boxes.DEFAULT_ID)
	profile=game.session.local_profile()
	assert(game.session.sanitize_profile(profile).safe_box_id==Boxes.DEFAULT_ID)
	game.safe_boxes.equip("safe_3x3")
	profile=game.session.local_profile()
	assert(game.session.sanitize_profile(profile).safe_box_id=="safe_3x3")
	if render: await capture_safes()
	if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
	print("SAFE BOX PASS: starter gift, task progress/claims, seasonal expiry, permanent fulfillment, save/load, continuous multi-cell cargo, overflow/rotation rollback, settlement, network dimensions")
	quit()

func capture_safes() -> void:
	DisplayServer.window_set_size(Vector2i(1440,900))
	game.state="menu"
	game.menu_tab="safe_boxes"
	game.safe_boxes=Boxes.new()
	game.safe_boxes.refresh_season()
	game.message_left=0
	await game.capture_frame("14-safe-boxes")
	game.safe_purchase_open=true
	await game.capture_frame("15-safe-purchase")
	game.safe_purchase_open=false
	game.safe_boxes.progress={"extracts":10,"value":150000,"kills":20}
	game.claim_safe_box("safe_2x2")
	game.claim_safe_box("safe_3x3")
	game.message_left=0
	await game.capture_frame("16-safe-tasks-complete")
	game.start_raid()
	game.overlay="inventory"
	game.set_capture()
	game.message_left=0
	for box in Boxes.CATALOGUE:
		game.configure_safe_box(game.player,box.id)
		game.player.safe_inventory=[Items.get_item("cpu"),Items.get_item("bolts")]
		if box.id!="safe_1x2": game.player.safe_inventory.append(Items.get_item("pliers"))
		game.inspected_index=-1
		await game.capture_frame("17-"+box.id)
