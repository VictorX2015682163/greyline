extends SceneTree

const Manual = preload("res://scripts/manual_safe_purchase.gd")
var fixture_path := ""
var capture := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--manual-fixture="): fixture_path=arg.trim_prefix("--manual-fixture=")
		if arg=="--capture-manual": capture=true
	call_deferred("run")

func run() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	var verifier=Manual.new(fixture.config)
	assert(verifier.key_ready and not verifier.can_receive_payment(),"No QR image must leave payment unavailable")
	assert(verifier.verify(fixture.code,fixture.buyer).ok,"Python/OpenSSL signature must verify in the actual Godot client")
	assert(verifier.verify(" \n"+fixture.code+"\r\n",fixture.buyer).ok)
	assert(not verifier.verify(fixture.code,"GL-00000000000000000000").ok,"Codes are bound to one saved buyer ID")
	for key in ["tampered","wrong_product","wrong_amount","foreign_key","bad_transaction"]:
		assert(not verifier.verify(fixture[key],fixture.buyer).ok,key+" must not unlock the box")
	for code in ["","GL1.a.b","GL1.!.*", "GL1."+"A".repeat(5000)+".AA"]:
		assert(not verifier.verify(code,fixture.buyer).ok)
	assert(not Manual.new(fixture.empty_config).verify(fixture.code,fixture.buyer).ok)
	var game=load("res://scenes/main.tscn").instantiate()
	game.smoke_mode=true
	game.profile_path="user://manual_safe_test_%d.json" % OS.get_process_id()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.manual_safe_purchase=verifier
	game.safe_boxes.purchase_id=fixture.buyer
	var bank_before: int=game.bank
	game.handle_ui("safe_purchase")
	assert(game.safe_purchase_open and not game.safe_boxes.available(game.SafeBoxes.PAID_ID))
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(game.profile_path))
	assert(saved.safe_boxes.purchase_id==fixture.buyer,"Buyer ID must be saved before displaying the collection code")
	game._input(InputEventKey.new())
	var enter:=InputEventKey.new()
	enter.physical_keycode=KEY_ENTER
	enter.pressed=true
	game._input(enter)
	assert(not game.start_requested,"Entering a redemption code cannot deploy into a raid")
	assert(not game.redeem_safe_purchase(fixture.tampered))
	assert(not game.safe_boxes.available(game.SafeBoxes.PAID_ID))
	if capture:
		DisplayServer.window_set_size(Vector2i(1440,900))
		game.menu_tab="safe_boxes"
		game.safe_purchase_message=""
		await game.capture_frame("21-manual-safe-payment")
	game.ui.purchase_code_edit.text=fixture.code
	game.ui.purchase_code_edit.text_submitted.emit(fixture.code)
	assert(game.safe_boxes.available(game.SafeBoxes.PAID_ID) and game.safe_boxes.equipped==game.SafeBoxes.PAID_ID)
	assert(game.safe_purchase_success and game.bank==bank_before,"Manual activation cannot spend game currency")
	var count: int=game.safe_boxes.transactions.size()
	assert(not game.redeem_safe_purchase(fixture.code))
	assert(game.safe_boxes.transactions.size()==count,"Redeeming twice is idempotent")
	game.safe_boxes=game.SafeBoxes.new()
	game.load_profile()
	assert(game.safe_boxes.purchase_id==fixture.buyer and game.safe_boxes.available(game.SafeBoxes.PAID_ID))
	if capture:
		game.ui.purchase_code_edit.clear()
		game.safe_purchase_message="激活成功！2 × 4 永久保险箱已装备。"
		await game.capture_frame("22-manual-safe-activated")
	var esc:=InputEventKey.new()
	esc.physical_keycode=KEY_ESCAPE
	esc.pressed=true
	game._input(esc)
	assert(not game.safe_purchase_open)
	assert(not game.redeem_safe_purchase(fixture.code),"Redemption is limited to the purchase dialog in the menu")
	if FileAccess.file_exists(game.profile_path): DirAccess.remove_absolute(game.profile_path)
	print("MANUAL SAFE PASS: signed activation, buyer binding, tamper rejection, isolated keys, receipt reuse protection, save/load, no currency spend, keyboard flow")
	quit()
