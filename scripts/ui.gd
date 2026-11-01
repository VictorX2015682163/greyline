class_name RaidUI
extends Control

const WeaponModsData = preload("res://scripts/weapon_mods.gd")
const ItemsData = preload("res://scripts/items.gd")
const EquipmentData = preload("res://scripts/equipment.gd")
const Equipment = preload("res://scripts/equipment.gd")
const SafeBoxes = preload("res://scripts/safe_boxes.gd")

const INK := Color("0c1419")
const PANEL := Color("142126")
const LINE := Color("334248")
const WHITE := Color("e8ede6")
const MUTED := Color("91a5a7")
const ORANGE := Color("e6b267")
const GREEN := Color("91c9ad")
const RED := Color("e88c78")
var game
var font: Font
var bold: Font
var latin: Font
var actions: Array = []
var mouse := Vector2.ZERO
var ui_time := 0.0
var purchase_code_edit: LineEdit

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var source: Font=load("res://assets/fonts/NotoSansSC.ttf")
	var regular:=FontVariation.new()
	regular.base_font=source
	regular.variation_opentype={2003265652:400.0}
	font=regular
	var heavy:=FontVariation.new()
	heavy.base_font=source
	heavy.variation_opentype={2003265652:700.0}
	bold=heavy
	latin=load("res://assets/fonts/BarlowSemiCondensed.ttf")
	purchase_code_edit=LineEdit.new()
	purchase_code_edit.placeholder_text="粘贴收款人发给你的专属激活码"
	purchase_code_edit.max_length=4096
	purchase_code_edit.add_theme_font_override("font",font)
	purchase_code_edit.add_theme_font_size_override("font_size",16)
	purchase_code_edit.text_submitted.connect(func(_value: String) -> void: game.handle_ui("safe_redeem"))
	purchase_code_edit.visible=false
	add_child(purchase_code_edit)

func _process(delta: float) -> void:
	ui_time+=delta
	mouse=get_local_mouse_position()/Vector2(size.x/1440.0,size.y/900.0)
	mouse_filter=Control.MOUSE_FILTER_IGNORE if game.accepts_player_input() else Control.MOUSE_FILTER_STOP
	var ui_scale:=Vector2(size.x/1440.0,size.y/900.0)
	purchase_code_edit.position=Vector2(586,540)*ui_scale
	purchase_code_edit.size=Vector2(550,46)
	purchase_code_edit.scale=ui_scale
	purchase_code_edit.visible=game.safe_purchase_open
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for action in actions:
			if action.rect.has_point(mouse):
				game.handle_ui(action.id)
				accept_event()
				return

func _draw() -> void:
	if not is_instance_valid(game): return
	draw_set_transform(Vector2.ZERO,0,Vector2(size.x/1440.0,size.y/900.0))
	actions.clear()
	if game.state=="menu":
		if game.menu_tab=="deploy": deployment()
		elif game.menu_tab=="armory": armory()
		elif game.menu_tab=="market": market()
		elif game.menu_tab=="stash": stash_screen()
		elif game.menu_tab=="safe_boxes": safe_boxes_screen()
		else: guide()
		navigation()
	elif game.state=="raid":
		hud()
		if game.overlay=="map": tactical_overlay()
		elif game.overlay=="inventory": inventory_screen()
		elif game.overlay=="search": inventory_screen(true)
		elif game.overlay=="pause": pause_screen()
	elif game.state=="result": result_screen()
	elif game.state=="matching": matchmaking_screen()
	if game.message_left>0 and (game.state!="raid" or not game.overlay.is_empty()):
		panel(Rect2(340,855,760,36),Color("26352f"),true)
		txt(game.message,357,880,14,ORANGE)
	if not game.storage_warning.is_empty(): txt(game.storage_warning,48,880,14,RED)
	if game.safe_purchase_open: safe_purchase_dialog()

func panel(rect: Rect2, color: Color=PANEL, border: bool=false) -> void:
	draw_rect(rect,color)
	if border: draw_rect(rect,LINE,false,1)

func txt(value: String, x: float, y: float, font_size: int=18, color: Color=WHITE, strong: bool=false) -> void:
	draw_string(bold if strong else font,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func en(value: String, x: float, y: float, font_size: int=18, color: Color=WHITE) -> void:
	draw_string(latin,Vector2(x,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func rule(x: float, y: float, width: float, color: Color=LINE) -> void:
	draw_line(Vector2(x,y),Vector2(x+width,y),color,1)

func button(id: String, rect: Rect2, title: String, primary: bool=false, small: bool=false) -> void:
	var hover:=rect.has_point(mouse)
	var color:=ORANGE if primary else Color("1b2b31")
	if hover: color=color.lightened(0.12)
	panel(rect,color,not primary)
	txt(title,rect.position.x+22,rect.position.y+rect.size.y/2+7,16 if small else 19,INK if primary else WHITE,true)
	if primary:
		var p:=rect.end-Vector2(27,rect.size.y/2)
		draw_line(p-Vector2(10,0),p+Vector2(7,0),INK,2)
		draw_line(p+Vector2(2,-5),p+Vector2(7,0),INK,2)
		draw_line(p+Vector2(2,5),p+Vector2(7,0),INK,2)
	actions.append({"id":id,"rect":rect})

func tag(title: String, x: float, y: float, color: Color=ORANGE, width: float=100) -> void:
	panel(Rect2(x,y,width,26),Color(color,0.13))
	draw_rect(Rect2(x,y,width,26),Color(color,0.45),false,1)
	txt(title,x+10,y+18,12,color)

func logo(x: float, y: float) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(x,y+30),Vector2(x+17,y),Vector2(x+34,y+30),Vector2(x+24,y+30),Vector2(x+17,y+17),Vector2(x+10,y+30)]),ORANGE)
	draw_line(Vector2(x-3,y+37),Vector2(x+37,y+37),ORANGE,3)

func navigation() -> void:
	panel(Rect2(0,0,1440,94),Color(0.035,0.065,0.08,0.97))
	logo(46,26)
	en("GREYLINE",100,51,27)
	txt("灰线行动",102,74,12,MUTED)
	var tabs:=[ ["deploy","作战部署"], ["armory","武器库"], ["market","装备采购"], ["stash","仓储"], ["safe_boxes","保险箱"], ["guide","行动指南"] ]
	for i in range(tabs.size()):
		var x:=290.0+i*128
		var active: bool=game.menu_tab==tabs[i][0]
		if active: panel(Rect2(x-14,0,120,94),Color("18262b"))
		txt(tabs[i][1],x,55,17,ORANGE if active else MUTED,active)
		if active: panel(Rect2(x-14,91,120,3),ORANGE)
		actions.append({"id":"tab:"+tabs[i][0],"rect":Rect2(x-14,0,120,94)})
	draw_circle(Vector2(1166,42),3.5,GREEN)
	txt("联机行动",1178,48,13,GREEN)
	en("¥ "+money(game.bank),1290,48,17)
	txt("本地档案  /  01",1278,72,11,MUTED)
	rule(0,94,1440)

func deployment() -> void:
	panel(Rect2(0,94,575,806),Color(0.035,0.065,0.08,0.97))
	for i in range(130): panel(Rect2(575+i*2,94,2,806),Color(0.035,0.065,0.08,0.96*(1-float(i)/130)))
	en("OPERATION 01  /  COASTAL INDUSTRIAL ZONE",48,155,12,ORANGE)
	txt("潮汐港",44,242,75,WHITE,true)
	en("T I D A L   P O R T",49,278,22,MUTED)
	tag("搜打撤",49,304,ORANGE,78)
	tag("6 人 · PvPvE",138,304,GREEN,116)
	tag("12 分钟",255,304,MUTED,98)
	txt("封锁后的港区，没有一条绝对安全的路线。",49,375,17,WHITE)
	txt("进入货运仓库，寻找失落物资。",49,408,17,MUTED)
	txt("在接应窗口关闭前，带着战利品离开。",49,438,17,MUTED)
	rule(49,471,462)
	var labels:=["地图范围","巡逻威胁","撤离窗口"]
	var values:=["220 × 200 m","14 名敌人","2 个接应点"]
	for i in range(3):
		var x:=49.0+i*160
		txt(labels[i],x,506,12,MUTED)
		en(values[i],x,539,21,WHITE) if i==0 else txt(values[i],x,539,20,WHITE,true)
	rule(49,568,462)
	en("INSERTION BRIEF",49,604,11,ORANGE)
	txt("01   搜索 8 类容器，管理格子与负重",49,640,15,WHITE)
	txt("02   利用掩体，留意枪声引来的巡逻队",49,672,15,WHITE)
	txt("03   进入绿区，坚守 10 秒完成撤离",49,704,15,WHITE)
	button("deploy",Rect2(49,752,462,66),"开始联机匹配",true)
	button("tab:market",Rect2(49,828,215,30),"前往装备采购",false,true)
	txt("普通可空装进入 · 机密仅检查战备值",280,848,12,MUTED)
	button("network_settings",Rect2(675,476,240,34),"联机设置 / 行动代号",false,true)
	txt("真人优先 · 等待 8 秒后 AI 补位",931,500,15,GREEN)
	en("27° 41′ N  /  121° 12′ E",824,142,13,WHITE)
	tag("港区现场 / 实时 3D",1176,123,GREEN,214)
	# A small tactical inset complements the live 3D port behind the menu.
	panel(Rect2(1090,172,300,288),Color(0.035,0.07,0.08,0.84),true)
	en("AO / 01",1108,200,12,ORANGE)
	txt("N ↑",1335,200,12,MUTED)
	map_draw(Rect2(1110,217,259,226),false)
	panel(Rect2(675,520,715,320),Color(0.035,0.065,0.08,0.94),true)
	panel(Rect2(675,520,4,320),ORANGE)
	en("SELECTED LOADOUT",699,552,11,MUTED)
	var carried: Dictionary=game.deployment_loadout()
	var weapon:=Arsenal.get_weapon(int(carried.weapon))
	txt(weapon.name,699,601,35)
	txt(weapon.type+"  /  "+weapon.caliber,700,635,14,MUTED)
	button("tab:armory",Rect2(700,666,166,34),"更换武器   →",false,true)
	# Keep the entire preview above the mode controls, including long weapons.
	if int(carried.weapon)>=0: draw_texture_rect(game.showcase_texture,Rect2(966,521,410,234),false)
	txt("精锐增援 · AI 干员更强" if game.raid_mode=="机密" else "标准巡逻 · 基础 AI 干员",699,724,14,ORANGE if game.raid_mode=="机密" else MUTED)
	txt("高品质物资概率提升 · 每箱至少 3 件" if game.raid_mode=="机密" else "标准物资概率 · 每箱 2–4 件",699,747,12,MUTED)
	rule(699,760,667)
	var mode_color:=GREEN if game.raid_mode=="普通" else ORANGE
	button("raidmode:普通",Rect2(699,786,112,36),"普通",game.raid_mode=="普通",true)
	button("raidmode:机密",Rect2(823,786,112,36),"机密",game.raid_mode=="机密",true)
	txt("战备值 ¥ "+money(game.loadout_readiness()),967,790,14,mode_color)
	txt("普通无战备门槛 / 机密准入 ¥ "+money(game.CLASSIFIED_READINESS),967,816,12,MUTED)
	en("FIELD BUILD / PROCUREMENT",1102,858,12,MUTED)

func matchmaking_screen() -> void:
	panel(Rect2(0,0,1440,900),Color(0.025,0.045,0.055,0.95))
	en("MATCHMAKING / TIDAL PORT",396,185,19,ORANGE)
	txt("正在集结行动人员",390,256,42,WHITE,true)
	txt(game.session.status_text,396,306,19,GREEN)
	rule(396,342,648)
	var row:=0
	for id in game.session.members:
		var member: Dictionary=game.session.members[id]
		txt("%02d   %s" % [row+1,str(member.get("name","行者"))],416,384+row*43,19,WHITE)
		row+=1
	for i in range(row,game.session.CAPACITY):
		txt("%02d   等待加入…" % (i+1),416,384+i*43,18,MUTED)
	txt("每局最多 6 名行动干员，空位由 AI 干员补齐。",396,680,16,MUTED)
	txt("AI 会搜索物资、交战和撤离；所有干员均可互相攻击。",396,712,15,MUTED)
	button("cancel_match",Rect2(396,760,648,60),"取消匹配")

func armory() -> void:
	panel(Rect2(0,94,1440,806),INK)
	for x in range(310,1050,45): draw_line(Vector2(x,110),Vector2(x,820),Color(0.15,0.22,0.24,0.19))
	for y in range(110,820,45): rule(310,y,740,Color(0.15,0.22,0.24,0.19))
	en("ARMORY / WEAPON WORKBENCH",33,139,12,ORANGE)
	txt("武器改装",31,179,29,WHITE,true)
	for i in range(8):
		var weapon:=Arsenal.get_weapon(i)
		var y:=206.0+i*71
		var selected: bool=game.selected_weapon==i
		var rect:=Rect2(32,y,246,61)
		panel(rect,Color("26362f") if selected else PANEL,true)
		if selected: panel(Rect2(32,y,3,61),ORANGE)
		en("0"+str(i+1),45,y+27,13,ORANGE)
		en(weapon.name,77,y+28,23,WHITE)
		txt(weapon.type,78,y+49,11,MUTED)
		if not game.build_for(i).is_empty(): tag(str(game.build_for(i).size())+" 改",216,y+20,GREEN,49)
		actions.append({"id":"weapon:"+str(i),"rect":rect})
	button("tab:market",Rect2(32,795,246,44),"采购武器 / 装备",false,true)
	var base:=Arsenal.get_weapon(game.selected_weapon)
	var build: Dictionary=game.build_for(game.selected_weapon)
	var current:=WeaponModsData.weapon(game.selected_weapon,build)
	en(current.name,320,174,43)
	txt(current.caliber,323,201,13,MUTED)
	tag("方案自动保存",869,151,GREEN,150)
	draw_texture_rect(game.showcase_texture,Rect2(292,277,758,278),false)
	for i in range(6):
		var slot: String=WeaponModsData.SLOTS[i]
		var x:=323.0+(i%3)*238
		var y:=228.0+(i/3)*323
		var chosen: bool=game.mod_slot==slot
		var rect:=Rect2(x,y,220,67)
		panel(rect,Color("26362f") if chosen else PANEL,true)
		if chosen: panel(Rect2(x,y,220,2),ORANGE)
		txt(WeaponModsData.SLOT_NAMES[slot],x+13,y+21,11,ORANGE if chosen else MUTED)
		var mod:=WeaponModsData.get_mod(str(build.get(slot,"")))
		txt(str(mod.get("name","原厂配置")),x+13,y+47,16,WHITE,true)
		actions.append({"id":"modslot:"+slot,"rect":rect})
		draw_line(Vector2(x+110,y+67 if i<3 else y),Vector2(x+110,y+87 if i<3 else y-20),LINE,1)
	en("PERFORMANCE / BASE → MODIFIED",324,656,12,ORANGE)
	var keys:=["recoil","spread","magazine","reload","range","weight"]
	var labels:=["后坐力","散布","弹匣","换弹 / s","射程 / m","重量 / kg"]
	for i in range(keys.size()):
		var key: String=keys[i]
		var x:=324.0+(i%2)*358
		var y:=697.0+(i/2)*49
		txt(labels[i],x,y,13,MUTED)
		var before:=float(base[key])
		var after:=float(current[key])
		var format_string: String="%.3f" if i<2 else ("%.2f" if i in [3,5] else "%.0f")
		var improved: bool=after<before if key in ["recoil","spread","reload","weight"] else after>before
		en((format_string % before)+"  /  "+(format_string % after),x+122,y,22,(GREEN if improved else RED) if not is_equal_approx(before,after) else WHITE)
	panel(Rect2(1060,120,347,719),PANEL,true)
	en("COMPONENTS / "+game.mod_slot.to_upper(),1080,150,12,ORANGE)
	txt(WeaponModsData.SLOT_NAMES[game.mod_slot]+"配置",1079,191,28,WHITE,true)
	txt("购买即安装 · 已拥有的配件免费切换",1080,218,12,MUTED)
	button("mod:none",Rect2(1080,240,307,49),"原厂配置"+("  / 当前" if not build.has(game.mod_slot) else ""),not build.has(game.mod_slot),true)
	var options:=WeaponModsData.options(game.selected_weapon,game.mod_slot)
	for i in range(options.size()):
		var mod: Dictionary=options[i]
		var y:=309.0+i*143
		var installed: bool=build.get(game.mod_slot,"")==mod.id
		var owned: bool=game.owned_gear.has("mod:"+str(mod.id))
		panel(Rect2(1080,y,307,132),Color("23322e") if installed else INK,true)
		panel(Rect2(1080,y,3,132),ItemsData.RARITY_COLORS[int(mod.rarity)])
		txt(mod.name,1094,y+28,18,WHITE,true)
		var details: PackedStringArray=str(mod.description).split(" · ")
		for n in range(mini(3,details.size())): txt(details[n],1094,y+51+n*18,11,MUTED)
		button("mod:"+str(mod.id),Rect2(1224,y+94,151,29),"已安装" if installed else ("安装" if owned else "¥ "+money(int(mod.price))),not installed,true)
		en("%+.2f kg" % float(mod.weight),1094,y+115,12,MUTED)
	if options.is_empty(): txt("此平台不支持该类配件。",1080,340,15,MUTED)
	txt("配件效果同步至实际战局与 3D 枪械。",1080,789,12,GREEN)
	txt("按 1–8 切换平台 · 未采购的武器不能部署",1080,816,12,MUTED)
	button("tab:deploy",Rect2(842,839,190,43),"返回部署",true,true)

func protection_icon(item: Dictionary, rect: Rect2, color: Color) -> void:
	var c:=rect.get_center()
	var k:=minf(rect.size.x,rect.size.y)*0.4
	if item.slot=="armor":
		var points:=PackedVector2Array([c+Vector2(-k*0.8,-k),c+Vector2(-k*0.3,-k),c+Vector2(0,-k*0.55),c+Vector2(k*0.3,-k),c+Vector2(k*0.8,-k),c+Vector2(k*0.6,-k*0.3),c+Vector2(k*0.8,k),c+Vector2(-k*0.8,k),c+Vector2(-k*0.6,-k*0.3),c+Vector2(-k*0.8,-k)])
		draw_colored_polygon(points,Color(color,0.16))
		draw_polyline(points,color,2)
		draw_rect(Rect2(c+Vector2(-k*0.38,-k*0.1),Vector2(k*0.76,k*0.75)),color,false,1.5)
	else:
		draw_arc(c+Vector2(0,k*0.15),k,PI,TAU,28,color,2.5)
		draw_line(c+Vector2(-k,k*0.15),c+Vector2(k,k*0.15),color,2.5)
		draw_line(c+Vector2(-k*0.75,k*0.15),c+Vector2(-k*0.6,k*0.8),color,2)
		draw_line(c+Vector2(k*0.75,k*0.15),c+Vector2(k*0.6,k*0.8),color,2)
		if item.variant=="hearing":
			for side in [-1,1]: draw_rect(Rect2(c+Vector2(side*k-k*0.12,-k*0.05),Vector2(k*0.24,k*0.8)),color,false,2)
		elif item.variant=="heavy": draw_rect(Rect2(c+Vector2(-k*0.7,k*0.28),Vector2(k*1.4,k*0.45)),Color(color,0.3),true)

func market() -> void:
	panel(Rect2(0,94,1440,806),INK)
	en("BASE / PROTECTION PROGRAM",49,144,12,ORANGE)
	txt("装备采购",46,202,43,WHITE,true)
	txt("1–6 级防护 · 三级起选择防护与机动 · 六级仅限稀有物资兑换",49,239,16,MUTED)
	panel(Rect2(1064,119,326,111),PANEL,true)
	txt("可用余额",1086,150,12,MUTED)
	en("¥ "+money(game.bank),1083,187,30,WHITE)
	txt("典藏咖啡  ×%d" % game.exchange_count(),1086,215,13,RED)
	var categories:=[["weapon","武器"],["armor","防弹衣"],["helmet","头盔"],["supply","补给"]]
	for i in range(categories.size()):
		button("market:"+categories[i][0],Rect2(49+i*165,264,151,39),categories[i][1],game.market_slot==categories[i][0],true)
	if game.market_slot in ["armor","helmet"]:
		protection_market()
	elif game.market_slot=="weapon":
		for i in range(8):
			var item:=Arsenal.get_weapon(i)
			var x:=49.0+(i%2)*474
			var y:=325.0+(i/2)*119
			var owned: bool=game.owned_gear.has("weapon:%d" % i)
			panel(Rect2(x,y,450,105),PANEL,true)
			en(item.name,x+18,y+34,26,WHITE)
			txt(item.type+" / "+item.caliber,x+18,y+60,12,MUTED)
			en("%.1f kg" % float(item.weight),x+18,y+87,13,MUTED)
			button("buy_weapon:"+str(i),Rect2(x+272,y+55,160,34),"装备" if owned else "¥ "+money(int(item.price)),not owned,true)
		panel(Rect2(1020,325,370,462),PANEL,true)
		en("WEAPON WORKBENCH",1042,365,14,ORANGE)
		txt("8 种平台 / 6 类改装位",1042,416,22,WHITE,true)
		txt("采购后前往武器库搭配瞄具、枪口、",1042,463,14,MUTED)
		txt("握把、弹匣、枪托与枪管。",1042,492,14,MUTED)
		button("tab:armory",Rect2(1042,701,326,53),"进入武器改装",true,true)
	else:
		var supplies:=EquipmentData.all_consumables()
		for i in range(supplies.size()):
			var item: Dictionary=supplies[i]
			var y:=325.0+i*207
			panel(Rect2(49,y,924,183),PANEL,true)
			txt(item.name,74,y+42,25,WHITE,true)
			txt(item.description,74,y+79,16,MUTED)
			var count: int=int(game.loadout.get("ammo_packs" if i==0 else "medkits",0))
			txt("已备 ×%d" % count,74,y+140,18,GREEN)
			button("buy_consumable:"+item.id,Rect2(707,y+111,241,45),"采购  ¥ "+money(int(item.unit_price)),true,true)
		panel(Rect2(1020,325,370,390),PANEL,true)
		txt("标准携行空间",1042,369,24,WHITE,true)
		txt("携行仓  6 × 4 格 / 20 kg",1042,424,17,WHITE)
		var safe_box: Dictionary=game.SafeBoxes.definition(game.safe_boxes.equipped)
		txt("保险箱  %d × %d 格" % [safe_box.columns,safe_box.rows],1042,464,17,GREEN)
		txt("无需采购背包或胸挂。",1042,524,15,MUTED)
		txt("弹药与急救包可按需携带。",1042,559,15,MUTED)
	panel(Rect2(49,825,1341,54),Color("111d21"),true)
	txt(loadout_summary(),68,858,14,WHITE)
	button("tab:deploy",Rect2(1170,832,205,38),"返回部署",true,true)

func protection_market() -> void:
	var items:=EquipmentData.gear_for_slot(game.market_slot)
	for i in range(items.size()):
		var item: Dictionary=items[i]
		var x:=49.0+(i%2)*474
		var y:=325.0+(i/2)*96
		var selected: bool=game.selected_gear==item.id
		var color: Color=ItemsData.RARITY_COLORS[int(item.tier)-1]
		var rect:=Rect2(x,y,450,84)
		panel(rect,Color("23352f") if selected else PANEL,true)
		panel(Rect2(x,y,3,84),color)
		protection_icon(item,Rect2(x+12,y+11,58,58),color)
		txt(item.name,x+84,y+28,19,WHITE,true)
		txt("吸收 %d%% · 耐久 %d" % [roundi(float(item.reduction)*100),int(item.armor)],x+84,y+53,13,MUTED)
		var status: String="已装备" if game.loadout.get(game.market_slot,"")==item.id else ("已解锁" if game.owned_gear.has(item.id) else ("典藏咖啡 ×1" if int(item.tier)==6 else "¥ "+money(int(item.price))))
		txt(status,x+302,y+29,13,GREEN if game.owned_gear.has(item.id) else color)
		en("%.1f kg" % float(item.weight),x+302,y+56,14,MUTED)
		actions.append({"id":"gearselect:"+item.id,"rect":rect})
	var selected:=EquipmentData.gear_item(game.selected_gear)
	if selected.is_empty() or selected.slot!=game.market_slot: selected=items[0]
	var color: Color=ItemsData.RARITY_COLORS[int(selected.tier)-1]
	panel(Rect2(1020,264,370,537),PANEL,true)
	tag("LEVEL 0%d" % int(selected.tier),1042,285,color,108)
	protection_icon(selected,Rect2(1272,277,90,83),color)
	txt(selected.name,1042,352,28,WHITE,true)
	var description: String=selected.description
	for n in range(ceili(description.length()/22.0)): txt(description.substr(n*22,22),1042,387+n*23,13,MUTED)
	var labels:=["伤害吸收","独立耐久","移动速度","冲刺耗能","开镜耗时","听觉范围"]
	var values:=["%d%%" % roundi(float(selected.reduction)*100),str(int(selected.armor)),"−%.1f%%" % (float(selected.speed_penalty)*100),"+%.1f%%" % (float(selected.stamina_penalty)*100),"+%.1f%%" % (float(selected.aim_penalty)*100),"%+.0f%%" % ((float(selected.hearing)-1)*100)]
	for i in range(labels.size()):
		var y:=454.0+i*32
		txt(labels[i],1042,y,14,MUTED)
		en(values[i],1264,y,21,color if i<2 else (GREEN if i==5 and float(selected.hearing)>1 else WHITE))
	rule(1042,638,326)
	var owned: bool=game.owned_gear.has(selected.id)
	var equipped: bool=game.loadout.get(game.market_slot,"")==selected.id
	if int(selected.tier)==6 and not owned:
		txt("1 罐典藏咖啡 → 1 件自选六级防具",1042,668,13,RED)
		txt("指定容器独立概率 0.3% · 带回后兑换",1042,693,12,MUTED)
		if game.exchange_count()>0:
			button("redeem:"+selected.id,Rect2(1042,714,326,47),"消耗 1 罐 · 兑换并装备",true,true)
		else:
			panel(Rect2(1042,714,326,47),Color("283033"),true)
			txt("缺少极地典藏咖啡",1064,744,16,MUTED,true)
	else:
		txt("解锁后可免费切换 · 入场恢复耐久",1042,677,13,GREEN)
		button("buy_gear:"+selected.id,Rect2(1042,714,326,47),"当前装备" if equipped and owned else ("免费装备" if owned else "采购并装备  ¥ "+money(int(selected.price))),not equipped or not owned,true)
	txt("头部 / 躯干独立防护 · 破损后不再吸收",1042,785,12,MUTED)

func loadout_summary() -> String:
	var carried: Dictionary=game.deployment_loadout()
	var weapon:=Arsenal.get_weapon(int(carried.weapon))
	var pieces: Array=[weapon.name]
	for slot in ["armor","helmet"]:
		var item:=EquipmentData.gear_item(str(carried.get(slot,"")))
		pieces.append(str(item.get("short","未携带防弹衣" if slot=="armor" else "未携带头盔")))
	return " / ".join(pieces)+"    战备值 ¥ "+money(game.loadout_readiness())

func map_point(pos: Vector3, rect: Rect2) -> Vector2:
	return rect.position+Vector2((pos.x+110)/220,(pos.z+100)/200)*rect.size

func map_draw(rect: Rect2, detailed: bool=true) -> void:
	panel(rect,Color("14252a"))
	for i in range(1,10):
		var x:=rect.position.x+rect.size.x*i/10
		var y:=rect.position.y+rect.size.y*i/10
		draw_line(Vector2(x,rect.position.y),Vector2(x,rect.end.y),Color("203339"))
		draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color("203339"))
	var road_x:=map_point(Vector3(24,0,0),rect).x
	var road_y:=map_point(Vector3(0,0,45),rect).y
	panel(Rect2(road_x-rect.size.x*0.025,rect.position.y,rect.size.x*0.05,rect.size.y),Color("314248"))
	panel(Rect2(rect.position.x,road_y-rect.size.y*0.027,rect.size.x,rect.size.y*0.054),Color("314248"))
	for shape in game.world.map_shapes:
		var r: Rect2=shape.rect
		var p:=map_point(Vector3(r.position.x,0,r.position.y),rect)
		var s:=r.size/Vector2(220,200)*rect.size
		panel(Rect2(p,s),Color("657d7c") if shape.color=="ivory" else Color("435e64"))
	for i in range(2):
		var p:=map_point(RaidWorld.EXITS[i],rect)
		draw_circle(p,7 if detailed else 4,Color(GREEN,0.2))
		draw_arc(p,8 if detailed else 5,0,TAU,24,GREEN,1.5)
		if detailed: txt("E"+str(i+1),p.x+13,p.y+5,14,GREEN,true)
	var spawn:=map_point(Vector3(-76,0,86),rect)
	if game.state=="menu":
		draw_circle(spawn,4,ORANGE)
		if detailed: txt("潜入点",spawn.x+11,spawn.y+4,13,ORANGE)
	if detailed:
		for chest in game.world.loot:
			if chest.get_meta("searched"): continue
			var p:=map_point(chest.position,rect)
			draw_rect(Rect2(p-Vector2(2,2),Vector2(4,4)),ORANGE)
		var zones:=[[Vector3(-75,0,-59),"A  海关办公区"],[Vector3(-8,0,-48),"B  货运仓库"],[Vector3(-69,0,0),"C  集装箱堆场"],[Vector3(66,0,-82),"D  储罐控制区"]]
		for zone in zones:
			var p:=map_point(zone[0],rect)
			txt(zone[1],p.x-38,p.y,12,WHITE,true)
	if game.state=="raid" and is_instance_valid(game.player):
		var p:=map_point(game.player.global_position,rect)
		var angle: float=-game.player.rotation.y
		var forward:=Vector2(sin(angle),-cos(angle))
		draw_colored_polygon(PackedVector2Array([p+forward*9,p+forward.rotated(2.5)*7,p+forward.rotated(-2.5)*7]),ORANGE)
	draw_rect(rect,LINE,false,1)

func money(amount: int) -> String:
	var result:=str(amount)
	var index:=result.length()-3
	while index>0:
		result=result.insert(index,",")
		index-=3
	return result

func clock_text(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds)/60,int(seconds)%60]

func hud() -> void:
	var p: RaidPlayer=game.player
	# Sparse edge framing keeps the world and reticle readable.
	panel(Rect2(0,0,1440,74),Color(0.025,0.045,0.055,0.78))
	en("GREYLINE",29,34,19)
	txt(game.world.zone_name(p.global_position),30,57,12,MUTED)
	if game.session.running:
		txt("联机 · %d 名行动干员" % game.session.combatants().size(),258,57,12,GREEN)
	var bearing:=fposmod(-rad_to_deg(p.rotation.y),360)
	for i in range(-4,5):
		var deg:=int(fposmod(roundf(bearing/15)*15+i*15,360))
		var x:=720.0+i*57-(bearing-float(roundi(bearing/15)*15))*3.8
		var label:=str(deg)
		if deg==0: label="N"
		elif deg==90: label="E"
		elif deg==180: label="S"
		elif deg==270: label="W"
		en(label,x-8,33,13,ORANGE if deg%90==0 else MUTED)
		draw_line(Vector2(x,44),Vector2(x,50),MUTED,1)
	draw_colored_polygon(PackedVector2Array([Vector2(715,5),Vector2(725,5),Vector2(720,11)]),ORANGE)
	en("EXFIL WINDOW",1230,26,10,MUTED)
	en(clock_text(game.raid_left),1271,57,28,RED if game.raid_left<120 else WHITE)
	if p.sound_left>0:
		panel(Rect2(611,84,218,34),Color(0.025,0.05,0.06,0.85),true)
		txt(p.sound_cue,633,108,14,GREEN)
	# Minimap and extraction information.
	panel(Rect2(28,96,192,204),Color(0.025,0.055,0.065,0.88),true)
	map_draw(Rect2(39,108,170,155),false)
	txt("潮汐港  /  M 展开地图",41,286,11,MUTED)
	panel(Rect2(28,309,218,99),Color(0.025,0.055,0.065,0.8))
	for i in range(2):
		var distance:=p.global_position.distance_to(RaidWorld.EXITS[i])
		var y:=330.0+i*43
		en("E"+str(i+1),31,y,13,GREEN)
		txt(RaidWorld.EXIT_NAMES[i],63,y,12,WHITE)
		en(str(int(distance))+" m",181,y,12,MUTED)
		if i==1 and game.RAID_LENGTH-game.raid_left<60: txt("接应准备中",64,y+17,10,ORANGE)
	# Reticle / telescopic scope.
	if p.aimed and float(p.weapon.aim_fov)<=36:
		draw_circle(Vector2(720,450),195,Color(0.02,0.04,0.045,0.08))
		draw_arc(Vector2(720,450),197,0,TAU,96,Color(0.02,0.035,0.04,0.9),7)
		draw_line(Vector2(525,450),Vector2(915,450),Color("1b2427"),1)
		draw_line(Vector2(720,255),Vector2(720,645),Color("1b2427"),1)
		for i in range(1,6): draw_line(Vector2(714,450+i*22),Vector2(726,450+i*22),Color("1b2427"),1)
		draw_circle(Vector2(720,450),2,RED)
	else:
		var gap:=5.0 if p.aimed else 9.0+p.recoil*110
		for axis in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			draw_line(Vector2(720,450)+axis*gap,Vector2(720,450)+axis*(gap+7),Color(WHITE,0.8),1.5)
		draw_circle(Vector2(720,450),1.3,ORANGE)
	if p.hit_flash>0:
		for v in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
			draw_line(Vector2(720,450)+v*12,Vector2(720,450)+v*20,ORANGE,2)
	if p.damage_flash>0:
		var a:=p.damage_flash*0.4
		panel(Rect2(0,0,18,900),Color(RED,a))
		panel(Rect2(1422,0,18,900),Color(RED,a))
		panel(Rect2(0,882,1440,18),Color(RED,a))
	# Contextual prompts.
	if is_instance_valid(game.current_loot) and game.overlay.is_empty():
		panel(Rect2(531,539,378,66),Color(0.025,0.05,0.06,0.9),true)
		tag("E",546,554,ORANGE,34)
		txt("搜索 "+str(ItemsData.CONTAINERS[game.current_loot.get_meta("kind")].name),595,576,17,WHITE,true)
		panel(Rect2(531,603,378,2),ORANGE)
	if game.extract_index>=0:
		panel(Rect2(485,146,470,91),Color(0.035,0.09,0.08,0.94),true)
		txt("正在撤离 · 请留在接应区",511,180,20,GREEN,true)
		en("%04.1f s" % maxf(0,10-game.extract_progress),813,181,25,GREEN)
		panel(Rect2(511,204,418,5),LINE)
		panel(Rect2(511,204,418*game.extract_progress/10,5),GREEN)
	if game.message_left>0:
		panel(Rect2(456,694,528,37),Color(0.025,0.05,0.06,0.85))
		txt(game.message,473,719,14,ORANGE)
	# Status and weapon panels.
	panel(Rect2(28,755,310,116),Color(0.025,0.05,0.06,0.9),true)
	en("OPERATOR / 01",45,779,10,MUTED)
	en(str(ceili(p.health)),45,821,34,WHITE if p.health>30 else RED)
	txt("生命",112,818,12,MUTED)
	txt("%d 级甲  %d/%d" % [p.armor_tier,ceili(p.armor),ceili(p.armor_cap)],178,783,12,MUTED)
	panel(Rect2(178,790,139,4),LINE)
	panel(Rect2(178,790,139*p.armor/maxf(1,p.armor_cap),4),Color("8dbacb"))
	txt("%d 级头  %d/%d" % [p.helmet_tier,ceili(p.helmet),ceili(p.helmet_cap)],178,813,12,MUTED)
	panel(Rect2(178,820,139,4),LINE)
	panel(Rect2(178,820,139*p.helmet/maxf(1,p.helmet_cap),4),ORANGE)
	panel(Rect2(45,836,272,6),LINE)
	panel(Rect2(45,836,272*p.health/100,6),GREEN if p.health>30 else RED)
	panel(Rect2(45,850,272,3),LINE)
	panel(Rect2(45,850,272*p.stamina/100,3),ORANGE)
	panel(Rect2(1122,755,290,116),Color(0.025,0.05,0.06,0.9),true)
	txt(p.weapon.name,1140,781,19)
	txt("空装" if p.weapon_index<0 else ("全自动" if p.weapon.automatic else "单发"),1329,781,12,ORANGE)
	en("%02d" % p.ammo,1140,834,45,ORANGE if p.ammo<6 else WHITE)
	en("/ "+str(p.reserve),1233,831,24,MUTED)
	txt("搜索物资，前往撤离点" if p.weapon_index<0 else p.weapon.caliber+"  ·  R 换弹",1142,856,12,MUTED)
	var progress:=0.0
	var progress_label:=""
	if p.reload_left>0:
		progress=1-p.reload_left/float(p.weapon.reload)
		progress_label="换弹中"
	elif p.heal_left>0:
		progress=1-p.heal_left/2.8
		progress_label="治疗中"
	if not progress_label.is_empty():
		txt(progress_label,680,624,16,ORANGE)
		panel(Rect2(620,642,200,4),LINE)
		panel(Rect2(620,642,200*progress,4),ORANGE)
	panel(Rect2(367,787,718,76),Color(0.025,0.05,0.06,0.8))
	txt("TAB 背包   "+str(snappedf(p.weight(),0.1))+" / "+str(int(p.capacity))+" kg",389,812,13,MUTED)
	txt("战利品  ¥ "+money(p.loot_value()),389,838,17,ORANGE,true)
	txt("H 急救包 ×"+str(p.meds)+"    M 地图    ESC 菜单",740,841,12,MUTED)

func overlay_base(title: String, subtitle: String) -> void:
	panel(Rect2(0,0,1440,900),Color(0.025,0.045,0.055,0.95))
	en(subtitle,61,71,13,ORANGE)
	txt(title,58,131,38,WHITE,true)
	button("resume",Rect2(1217,48,166,44),"返回行动  ×",false,true)
	rule(60,164,1320)

func tactical_overlay() -> void:
	overlay_base("潮汐港 / 战术地图","TACTICAL OVERVIEW")
	map_draw(Rect2(71,198,685,622),true)
	txt("撤离接应",825,238,24,WHITE,true)
	for i in range(2):
		var y:=285.0+i*120
		tag("E"+str(i+1),825,y,GREEN,40)
		txt(RaidWorld.EXIT_NAMES[i],883,y+20,19,WHITE,true)
		txt("进入标记区，持续停留 10 秒",825,y+57,15,MUTED)
		var ready: bool=i==0 or game.RAID_LENGTH-game.raid_left>=60
		txt("接应就绪" if ready else "开局 60 秒后开放",825,y+83,13,GREEN if ready else ORANGE)
	rule(825,547,480)
	txt("橙色方块   可搜索容器",825,586,16,ORANGE)
	txt("橙色箭头   你的当前位置与朝向",825,627,16,WHITE)
	txt("越靠近储罐区，物资价值与威胁越高。",825,698,16,MUTED)
	txt("联机行动持续进行，查看地图时请注意隐蔽。",825,734,14,ORANGE)

func item_icon(item: Dictionary, rect: Rect2, color: Color) -> void:
	var center:=rect.get_center()
	var k:=minf(rect.size.x,rect.size.y)*0.28
	var icon: String=str(item.get("icon","parts"))
	if icon=="medical":
		draw_rect(Rect2(center-Vector2(k*0.26,k),Vector2(k*0.52,k*2)),color)
		draw_rect(Rect2(center-Vector2(k,k*0.26),Vector2(k*2,k*0.52)),color)
	elif icon in ["chip","drive"]:
		draw_rect(Rect2(center-Vector2(k,k*0.7),Vector2(k*2,k*1.4)),color,false,2)
		draw_rect(Rect2(center-Vector2(k*0.46,k*0.4),Vector2(k*0.92,k*0.8)),Color(color,0.4))
		for i in range(4):
			draw_line(center+Vector2(-k*0.8+i*k*0.53,-k),center+Vector2(-k*0.8+i*k*0.53,-k*0.7),color,2)
			draw_line(center+Vector2(-k*0.8+i*k*0.53,k),center+Vector2(-k*0.8+i*k*0.53,k*0.7),color,2)
	elif icon in ["optic","attachment"]:
		draw_circle(center,k,Color(color,0.14))
		draw_arc(center,k,0,TAU,28,color,2)
		draw_line(center-Vector2(k*1.3,0),center+Vector2(k*1.3,0),color,1)
		draw_line(center-Vector2(0,k*1.3),center+Vector2(0,k*1.3),color,1)
	elif icon=="ammo":
		for i in range(3):
			var x:=center.x-k*0.7+i*k*0.7
			draw_rect(Rect2(x-k*0.19,center.y-k*0.5,k*0.38,k*1.3),color,false,2)
			draw_colored_polygon(PackedVector2Array([Vector2(x-k*0.19,center.y-k*0.5),Vector2(x,center.y-k),Vector2(x+k*0.19,center.y-k*0.5)]),color)
	elif icon=="coffee":
		draw_rect(Rect2(center-Vector2(k*0.65,k*0.8),Vector2(k*1.3,k*1.6)),Color(color,0.14))
		draw_rect(Rect2(center-Vector2(k*0.65,k*0.8),Vector2(k*1.3,k*1.6)),color,false,2)
		draw_line(center+Vector2(-k*0.8,-k*0.85),center+Vector2(k*0.8,-k*0.85),color,3)
		draw_arc(center,k*0.42,-0.4,TAU-0.4,20,color,2)
		draw_line(center+Vector2(-k*0.2,k*0.28),center+Vector2(k*0.2,-k*0.28),color,1.5)
	elif icon=="valuable":
		draw_colored_polygon(PackedVector2Array([center+Vector2(0,-k),center+Vector2(k,0),center+Vector2(0,k),center-Vector2(k,0)]),Color(color,0.4))
		draw_polyline(PackedVector2Array([center+Vector2(0,-k),center+Vector2(k,0),center+Vector2(0,k),center-Vector2(k,0),center+Vector2(0,-k)]),color,2)
	elif icon=="document":
		draw_rect(Rect2(center-Vector2(k*0.7,k),Vector2(k*1.4,k*2)),color,false,2)
		for i in range(3): draw_line(center+Vector2(-k*0.4,-k*0.4+i*k*0.4),center+Vector2(k*0.4,-k*0.4+i*k*0.4),color,1)
	elif icon=="tool":
		draw_line(center-Vector2(k*0.6,-k*0.7),center+Vector2(k*0.5,-k*0.6),color,5)
		draw_arc(center+Vector2(k*0.55,-k*0.6),k*0.4,-0.5,PI+0.5,12,color,3)
	else:
		draw_rect(Rect2(center-Vector2(k*0.8,k*0.75),Vector2(k*1.6,k*1.5)),Color(color,0.18))
		draw_rect(Rect2(center-Vector2(k*0.8,k*0.75),Vector2(k*1.6,k*1.5)),color,false,2)
		draw_line(center-Vector2(0,k*0.75),center+Vector2(0,k*0.75),color,2)

func connected_grid(origin: Vector2, columns: int, rows: int, cell: float, color: Color=GREEN) -> void:
	var rect:=Rect2(origin,Vector2(columns,rows)*cell)
	panel(rect,Color("111e23"))
	for x in range(1,columns): draw_line(origin+Vector2(x*cell,0),origin+Vector2(x*cell,rows*cell),LINE,1)
	for y in range(1,rows): draw_line(origin+Vector2(0,y*cell),origin+Vector2(columns*cell,y*cell),LINE,1)
	draw_rect(rect,color,false,2)

func safe_boxes_screen() -> void:
	panel(Rect2(0,94,1440,806),INK)
	var boxes=game.safe_boxes
	en("BASE / SECURE CONTAINERS",49,144,13,ORANGE)
	txt("保险箱",46,201,40,WHITE,true)
	txt("开局赠送基础箱 · 完成任务领取赛季箱 · 永久箱单独购买",49,237,15,MUTED)
	tag(boxes.season,1125,131,GREEN,265)
	txt("本赛季截至 "+SafeBoxes.season_deadline(boxes.season),942,204,13,MUTED)
	var current: String=game.safe_box_label(boxes.equipped)
	txt("当前装备："+current,1045,238,16,GREEN,true)
	for i in range(SafeBoxes.CATALOGUE.size()):
		var box: Dictionary=SafeBoxes.CATALOGUE[i]
		var x:=49.0+i*340
		var active: bool=boxes.equipped==box.id
		var owned: bool=boxes.available(box.id)
		var color:=ORANGE if box.access=="purchase" else GREEN
		panel(Rect2(x,276,321,513),PANEL,true)
		if active: draw_rect(Rect2(x,276,321,513),GREEN,false,2)
		en("%d × %d" % [int(box.columns),int(box.rows)],x+22,326,34,WHITE)
		txt(box.name,x+155,322,17,WHITE,true)
		var access: String="开局赠送 · 永久" if box.access=="starter" else ("人民币 10 元 · 永久" if box.access=="purchase" else "任务获取 · 本赛季有效")
		txt(access,x+22,357,14,color)
		var cell:=37.0
		var origin:=Vector2(x+(321-int(box.columns)*cell)/2,380+(148-int(box.rows)*cell)/2)
		connected_grid(origin,int(box.columns),int(box.rows),cell,color)
		txt("%d 格连续空间" % (int(box.columns)*int(box.rows)),x+22,557,14,MUTED)
		if box.access=="season":
			var task_names: Dictionary={"extracts":"成功撤离","value":"成功带回物资价值","kills":"击杀目标"}
			var n:=0
			for key in box.goals:
				var goal:=int(box.goals[key])
				var value:=mini(goal,int(boxes.progress.get(key,0)))
				var progress_text: String="%s / %s" % [money(value),money(goal)] if key=="value" else "%d / %d" % [value,goal]
				txt(task_names[key],x+22,589+n*35,12,MUTED)
				txt(progress_text,x+175,589+n*35,12,GREEN if value>=goal else WHITE)
				n+=1
		elif box.access=="purchase":
			txt("一次购买，跨赛季保留权限。",x+22,597,14,WHITE)
			txt("独立人民币商品",x+22,629,13,MUTED)
		else:
			txt("所有干员自动获得。",x+22,597,14,WHITE)
			txt("无任务门槛，随时可装备。",x+22,629,13,MUTED)
		if active:
			tag("已装备",x+22,720,GREEN,277)
		elif owned:
			button("safe_equip:"+box.id,Rect2(x+22,709,277,49),"装备保险箱",false,true)
		elif box.access=="purchase":
			button("safe_purchase",Rect2(x+22,709,277,49),"查看购买 · 10 元永久",true,true)
		elif boxes.task_complete(box.id):
			button("safe_claim:"+box.id,Rect2(x+22,709,277,49),"领取赛季权限并装备",true,true)
		else:
			tag("完成以上任务后领取",x+22,720,MUTED,277)
	txt("所有格子相连，可容纳跨格物品；阵亡、超时或放弃时，箱内物资仍会带回。",49,826,14,GREEN)
	txt("任务从本赛季行动结算累计；赛季结束重置任务与赛季权限，永久权限保留。",49,852,13,MUTED)

func safe_purchase_dialog() -> void:
	actions.clear()
	panel(Rect2(0,0,1440,900),Color(0.02,0.035,0.045,0.91))
	panel(Rect2(270,135,900,660),PANEL,true)
	en("WECHAT PAYMENT / MANUAL ACTIVATION",304,175,13,ORANGE)
	txt("2 × 4 永久保险箱",304,220,29,WHITE,true)
	txt("人民币 10 元",943,217,25,ORANGE,true)
	rule(304,245,832)
	var purchase=game.manual_safe_purchase
	var owned: bool=game.safe_boxes.available(SafeBoxes.PAID_ID)
	var payment_ready: bool=purchase.can_receive_payment() and game.storage_warning.is_empty() and not owned
	var qr_rect:=Rect2(304,270,240,240)
	if payment_ready:
		panel(qr_rect,Color.WHITE)
		var extent: Vector2=purchase.qr_texture.get_size()
		var fit:=minf(224/extent.x,224/extent.y)
		var image_size: Vector2=extent*fit
		draw_texture_rect(purchase.qr_texture,Rect2(qr_rect.get_center()-image_size/2,image_size),false)
	else:
		panel(qr_rect,INK,true)
		txt("已永久解锁" if owned else "微信收款码待开放",325,378,21,GREEN if owned else MUTED,true)
		txt("无需重复付款" if owned else "当前不可扫码付款",338,413,16,MUTED)
	txt("微信扫码 · ¥10.00",304,549,20,ORANGE,true)
	connected_grid(Vector2(304,579),2,4,23,ORANGE)
	txt("8 格连续空间",372,602,15,WHITE,true)
	txt("一次购买",372,632,14,MUTED)
	txt("跨赛季永久保留",372,660,14,GREEN)
	txt("扫码付款，人工核对后解锁",586,294,21,WHITE,true)
	txt("1  微信扫描左侧收款码，支付 10 元。",586,333,15,MUTED)
	txt("2  将付款凭证和购买编号微信发给收款人。",586,367,15,MUTED)
	txt("3  收到专属激活码后，粘贴到下方激活。",586,401,15,MUTED)
	var contact: String=str(purchase.config.get("wechat_contact",""))
	txt("微信："+contact if not contact.is_empty() else "请通过你与收款人的微信联系渠道发送。",586,430,13,GREEN)
	panel(Rect2(586,444,550,74),INK,true)
	txt("你的购买编号（与本机档案绑定）",602,467,12,MUTED)
	en(game.safe_boxes.purchase_id,602,499,21,WHITE)
	button("safe_copy_id",Rect2(992,464,130,36),"复制编号",false,true)
	button("safe_redeem",Rect2(586,600,550,46),"验证激活码并永久解锁",true,true)
	var status: String=game.safe_purchase_message
	if not game.storage_warning.is_empty(): status="购买编号未能保存，请先解决存档问题，暂勿付款。"
	if status.is_empty(): status="人工核对到账后发码；付款本身不会自动解锁。"
	txt(status,586,675,13,GREEN if game.safe_purchase_success else MUTED)
	rule(304,713,832)
	txt("请保留付款凭证和本机存档，以便核对或恢复权限。",304,752,14,MUTED)
	button("safe_purchase_close",Rect2(960,731,176,42),"返回保险箱",false,true)

func item_grid(items: Array, source: String, origin: Vector2, columns: int, rows: int, cell: float, revealed: int=-1) -> void:
	var connected:=source=="safe"
	if connected:
		connected_grid(origin,columns,rows,cell)
	else:
		for y in range(rows):
			for x in range(columns):
				panel(Rect2(origin+Vector2(x,y)*cell,Vector2.ONE*(cell-3)),Color("111e23"),true)
	var positions:=ItemsData.pack(items,columns,rows)
	if positions.size()!=items.size(): return
	for i in range(items.size()):
		var item: Dictionary=items[i]
		var known:=revealed<0 or i<revealed
		var extent:=ItemsData.grid_size(item)
		var rect:=Rect2(origin+Vector2(positions[i])*cell,Vector2(extent)*cell-Vector2.ONE*(0 if connected else 3))
		var rarity:=clampi(int(item.get("rarity",0)),0,5)
		var color: Color=ItemsData.RARITY_COLORS[rarity] if known else LINE
		panel(rect,Color(color,0.13) if known else Color("1b2b30"))
		draw_rect(rect,color if game.inspected_source==source and game.inspected_index==i else Color(color,0.5),false,2 if game.inspected_source==source and game.inspected_index==i else 1)
		if known:
			panel(Rect2(rect.position.x,rect.end.y-3,rect.size.x,3),color)
			item_icon(item,Rect2(rect.position+Vector2(10,8),rect.size-Vector2(20,25)),color)
			var item_name: String=str(item.name)
			if extent.x==1 and item_name.length()>4: item_name=item_name.substr(0,4)
			txt(item_name,rect.position.x+6,rect.end.y-9,10 if cell<80 else 12,WHITE)
			actions.append({"id":"inspect:"+source+":"+str(i),"rect":rect})
		else:
			en("?",rect.get_center().x-7,rect.get_center().y+9,29,MUTED)

func equipment_panel() -> void:
	var p: RaidPlayer=game.player
	panel(Rect2(32,181,235,655),PANEL,true)
	en("OPERATOR / 01",49,209,12,ORANGE)
	txt("作战装备",48,242,22,WHITE,true)
	panel(Rect2(49,259,201,70),INK,true)
	txt(p.weapon.name,63,289,25,WHITE)
	txt("配件 "+str(p.weapon.mod_count)+" / 6",63,314,12,GREEN)
	var slots:=["armor","helmet"]
	for i in range(2):
		var y:=350.0+i*93
		var item:=Equipment.gear_item(str(game.loadout.get(slots[i],"")))
		txt("防弹衣" if i==0 else "头盔",49,y,11,MUTED)
		txt(str(item.get("name","未装备")),49,y+25,18,WHITE,true)
		var durability: float=p.armor if i==0 else p.helmet
		var cap: float=p.armor_cap if i==0 else p.helmet_cap
		txt("耐久 %d / %d · 吸收 %d%%" % [ceili(durability),ceili(cap),roundi(float(item.get("reduction",0))*100)],49,y+49,12,GREEN if durability>0 else RED)
		rule(49,y+65,201)
	txt("移动速度  −%.1f%%" % ((1-p.movement_multiplier())*100),49,554,13,MUTED)
	txt("冲刺耗能  +%.1f%%" % (p.stamina_penalty*100),49,581,13,MUTED)
	txt("开镜耗时  +%.1f%%" % (p.aim_penalty*100),49,608,13,MUTED)
	txt("听觉范围  %+.0f%%" % ((p.hearing-1)*100),49,635,13,GREEN if p.hearing>1 else MUTED)
	txt("生命 %d / 100" % ceili(p.health),49,680,16,WHITE,true)
	txt("备弹 %d 发   急救包 ×%d" % [p.reserve,p.meds],49,710,12,MUTED)
	txt("携行价值",49,749,12,MUTED)
	en("¥ "+money(p.loot_value()),48,784,29,ORANGE)
	txt("联机行动继续 · 搜索时注意掩护",49,818,11,ORANGE)

func inventory_screen(searching: bool=false) -> void:
	overlay_base("搜索与回收" if searching else "战术背包","SEARCH / DISCOVER / EXTRACT" if searching else "FIELD INVENTORY / EVERY SLOT COUNTS")
	var p: RaidPlayer=game.player
	equipment_panel()
	txt("战术背包",293,210,20,WHITE,true)
	en("%02d / %02d SLOTS" % [ItemsData.used_cells(p.inventory),p.bag_columns*p.bag_rows],488,207,13,MUTED)
	button("sort_bag",Rect2(659,182,125,36),"整理背包",false,true)
	var cell:=78.0 if p.bag_rows<=4 else 62.0
	item_grid(p.inventory,"bag",Vector2(294,238),p.bag_columns,p.bag_rows,cell)
	var bag_bottom:=238+p.bag_rows*cell
	panel(Rect2(294,bag_bottom+15,468,5),LINE)
	panel(Rect2(294,bag_bottom+15,468*clampf(p.weight()/p.capacity,0,1),5),ORANGE)
	txt("负重  %.2f / %.0f kg" % [p.weight(),p.capacity],294,bag_bottom+43,13,MUTED)
	txt("保险箱  /  %d × %d" % [p.safe_columns,p.safe_rows],294,bag_bottom+84,17,GREEN,true)
	var safe_origin:=Vector2(294,bag_bottom+102)
	var safe_cell:=minf(56.0,(831.0-safe_origin.y)/p.safe_rows)
	item_grid(p.safe_inventory,"safe",safe_origin,p.safe_columns,p.safe_rows,safe_cell)
	var note_x:=safe_origin.x+p.safe_columns*safe_cell+20
	txt("阵亡、超时或放弃时仍可带回。",note_x,safe_origin.y+25,12,MUTED)
	txt("连续空间 · 可放入跨格物品",note_x,safe_origin.y+49,12,GREEN)
	txt("%d / %d 格已用" % [ItemsData.used_cells(p.safe_inventory),p.safe_columns*p.safe_rows],note_x,safe_origin.y+73,12,MUTED)
	if searching and is_instance_valid(game.search_container):
		var chest: Node3D=game.search_container
		var contents: Array=chest.get_meta("items")
		var revealed:=int(chest.get_meta("revealed"))
		var profile: Dictionary=ItemsData.CONTAINERS[chest.get_meta("kind")]
		txt(chest.get_meta("label"),827,211,21,WHITE,true)
		txt(profile.hint,827,237,12,MUTED)
		var status: String="搜索完成" if revealed>=contents.size() else ("搜索已暂停" if game.search_paused else "正在搜索未知物品…")
		txt(status,827,274,14,GREEN if revealed>=contents.size() else ORANGE)
		en("%02d / %02d" % [revealed,contents.size()],1289,273,17,MUTED)
		panel(Rect2(827,291,534,4),LINE)
		var fraction:=1.0 if revealed>=contents.size() else float(chest.get_meta("search_elapsed"))/float(profile.time)
		panel(Rect2(827,291,534*fraction,4),GREEN if revealed>=contents.size() else ORANGE)
		item_grid(contents,"loot",Vector2(827,314),6,4,89,revealed)
		if contents.is_empty():
			txt("容器已清空",991,488,23,MUTED,true)
		button("take_all",Rect2(1108,691,252,42),"拾取已发现物品",true,true)
		if revealed<contents.size(): button("search_toggle",Rect2(827,691,249,42),"继续搜索" if game.search_paused else "暂停搜索",false,true)
		txt("点击物品查看详情，再选择拾取。",827,764,13,MUTED)
		txt("关闭后保留搜索进度，可以再次打开。",827,791,13,MUTED)
		txt("未知物品需要逐件搜索后才能拿取。",827,818,13,MUTED)
	else:
		panel(Rect2(827,183,534,179),PANEL,true)
		en("CARGO / KEEP WHAT MATTERS",850,216,13,ORANGE)
		txt("为高价值物资留出空间。",850,263,25,WHITE,true)
		txt("物品大小、品质与单格价值决定携行选择。",850,298,14,MUTED)
		txt("选中物品可使用、旋转、丢弃或放入安全箱。",850,330,14,MUTED)
		for i in range(6): tag(ItemsData.RARITY_NAMES[i],829+(i%3)*177,391+(i/3)*40,ItemsData.RARITY_COLORS[i],162)
		txt("搜到的配件在撤离后解锁基地改装。",829,513,15,MUTED)
		txt("带回的物资进入仓库，可选择出售。",829,547,15,MUTED)
	item_details()

func item_details() -> void:
	var item: Dictionary=game.selected_item()
	if item.is_empty(): return
	# A fixed inspector replaces the right pane while preserving both cargo grids.
	var source: String=game.inspected_source
	var in_search: bool=game.state=="raid" and game.overlay=="search"
	var y:=747.0 if in_search else 590.0
	var h:=90.0 if in_search else 247.0
	if in_search:
		panel(Rect2(812,y,574,h),Color("1b2b30"),true)
		txt(item.name,828,y+27,18,ItemsData.RARITY_COLORS[clampi(int(item.get("rarity",0)),0,5)],true)
		txt("¥ "+money(int(item.value))+" · %.2f kg · %d × %d" % [float(item.weight),ItemsData.grid_size(item).x,ItemsData.grid_size(item).y],828,y+52,12,MUTED)
	else:
		panel(Rect2(827,y,534,h),PANEL,true)
		item_icon(item,Rect2(844,y+17,65,65),ItemsData.RARITY_COLORS[clampi(int(item.get("rarity",0)),0,5)])
		txt(item.name,928,y+35,22,WHITE,true)
		txt(str(item.get("category","回收物资"))+" / "+ItemsData.RARITY_NAMES[clampi(int(item.get("rarity",0)),0,5)],928,y+62,12,MUTED)
		txt("价值 ¥ "+money(int(item.value))+"   /   %.2f kg   /   %d × %d 格" % [float(item.weight),ItemsData.grid_size(item).x,ItemsData.grid_size(item).y],849,y+107,14,ORANGE)
		var description: String=str(item.get("description","旧版带回物资。"))
		for n in range(mini(2,ceili(description.length()/31.0))): txt(description.substr(n*31,31),849,y+140+n*24,12,MUTED)
	var action_y:=y+62 if in_search else y+193
	if source=="loot": button("take:"+str(game.inspected_index),Rect2(1234,action_y-35 if in_search else action_y,135,32),"拾取",true,true)
	elif source in ["bag","safe"]:
		var action_x:=827.0 if in_search else 848.0
		var action_top:=y+62 if in_search else action_y
		button("secure",Rect2(action_x,action_top,142,28),"放入安全箱" if source=="bag" else "移回背包",false,true)
		button("rotate",Rect2(action_x+150,action_top,94,28),"旋转 R",false,true)
		if item.has("heal") or item.has("ammo"): button("use_item",Rect2(action_x+252,action_top,94,28),"使用",true,true)
		button("discard",Rect2(action_x+354,action_top,94,28),"丢弃",false,true)

func pause_screen() -> void:
	panel(Rect2(0,0,1440,900),Color(0.025,0.045,0.055,0.88))
	en("OPERATION / MENU",529,286,13,ORANGE)
	txt("行动菜单",525,348,44,WHITE,true)
	txt("联机战局仍在进行，请在安全位置操作。",529,391,17,ORANGE)
	button("resume",Rect2(529,433,382,60),"继续行动",true)
	button("abort",Rect2(529,511,382,57),"放弃本局物资 · 返回基地")
	txt("WASD 移动  ·  Shift 冲刺  ·  空格 跳跃",529,628,14,MUTED)
	txt("左键 开火  ·  右键 瞄准  ·  R 换弹",529,663,14,MUTED)
	txt("E 搜索  ·  H 治疗  ·  Tab 背包  ·  M 地图",529,698,14,MUTED)

func result_screen() -> void:
	panel(Rect2(0,0,1440,900),Color(0.025,0.045,0.055,0.97))
	var color:=GREEN if game.result_success else RED
	en("AFTER ACTION REPORT",75,92,14,color)
	logo(1309,58)
	txt("撤离成功" if game.result_success else "行动失败",69,210,70,color,true)
	txt(game.result_reason,75,255,20,MUTED)
	rule(75,297,1290)
	var p: RaidPlayer=game.player
	var labels:=["本次带回价值","清除威胁","行动用时","消耗弹药"]
	var values:=["¥ "+money(p.loot_value() if game.result_success else p.safe_value()),str(game.kills),clock_text(game.RAID_LENGTH-game.raid_left),str(game.shots)]
	for i in range(4):
		var x:=77.0+i*330
		txt(labels[i],x,348,14,MUTED)
		en(values[i],x,412,42,WHITE)
	rule(75,453,1290)
	txt("物资已转入仓储" if game.result_success else "背包物资遗失 · 安全箱已带回 %d 件" % p.safe_inventory.size(),75,501,22,color,true)
	var cargo: Array=p.inventory+p.safe_inventory if game.result_success else p.safe_inventory
	var shown:=mini(8,cargo.size())
	for i in range(shown):
		var item: Dictionary=cargo[i]
		var x:=75.0+(i%4)*328
		var y:=536.0+(i/4)*84
		panel(Rect2(x,y,310,72),PANEL,true)
		txt(item.name,x+17,y+29,17,WHITE)
		en("¥ "+money(item.value),x+17,y+54,13,MUTED)
	if shown==0: txt("本次没有携行战利品",75,567,17,MUTED)
	button("return",Rect2(1039,762,326,65),"返回基地",true)
	en("BALANCE  /  ¥ "+money(game.bank),76,800,21,WHITE)
	txt("带回物资可在仓库出售；搜到的配件已解锁改装。",76,839,14,MUTED)

func stash_screen() -> void:
	panel(Rect2(0,94,1440,806),INK)
	en("BASE / SECURED CARGO",49,145,13,ORANGE)
	txt("回收仓库",46,202,40,WHITE,true)
	txt("带回物资后出售 · 配件自动解锁 · 典藏咖啡可兑换六级防具",49,238,15,MUTED)
	panel(Rect2(1030,120,360,124),PANEL,true)
	txt("可用余额",1051,151,12,MUTED)
	en("¥ "+money(game.bank),1048,194,34,WHITE)
	en("RAIDS "+str(game.raids)+" / EXTRACTED "+str(game.escaped),1051,226,12,GREEN)
	var filters:=["全部","电子设备","武器配件","医疗用品","贵重物品","其他"]
	for i in range(filters.size()): button("stashfilter:"+filters[i],Rect2(49+i*155,270,142,36),filters[i],game.stash_filter==filters[i],true)
	var matching: Array=[]
	for i in range(game.stash.size()):
		var item: Dictionary=game.stash[i]
		var category: String=str(item.get("category","其他"))
		if game.stash_filter=="全部" or category==game.stash_filter or (game.stash_filter=="其他" and category not in ["电子设备","武器配件","医疗用品","贵重物品"]): matching.append(i)
	var pages:=maxi(1,ceili(matching.size()/12.0))
	game.stash_page=clampi(game.stash_page,0,pages-1)
	for n in range(mini(12,matching.size()-game.stash_page*12)):
		var index: int=matching[n+game.stash_page*12]
		var item: Dictionary=game.stash[index]
		var x:=49.0+(n%4)*238
		var y:=329.0+(n/4)*146
		var rarity:=clampi(int(item.get("rarity",0)),0,5)
		var rect:=Rect2(x,y,220,130)
		panel(rect,Color(ItemsData.RARITY_COLORS[rarity],0.1),true)
		panel(Rect2(x,y,3,130),ItemsData.RARITY_COLORS[rarity])
		item_icon(item,Rect2(x+13,y+13,65,65),ItemsData.RARITY_COLORS[rarity])
		txt(item.name,x+16,y+97,16,WHITE,true)
		en("¥ "+money(int(item.value)),x+16,y+119,13,ORANGE)
		txt(ItemsData.RARITY_NAMES[rarity],x+150,y+28,11,ItemsData.RARITY_COLORS[rarity])
		en("%.2f kg" % float(item.weight),x+142,y+51,12,MUTED)
		actions.append({"id":"inspect:stash:"+str(index),"rect":rect})
	if matching.is_empty():
		en("NO SECURED CARGO",65,444,32,LINE)
		txt("还没有这类物资，去港区搜索并成功撤离。",65,485,18,MUTED)
	txt("共 %d 件物资" % matching.size(),49,815,13,MUTED)
	button("stashpage:-1",Rect2(597,785,126,38),"上一页",false,true)
	en("%02d / %02d" % [game.stash_page+1,pages],750,811,18,MUTED)
	button("stashpage:1",Rect2(853,785,126,38),"下一页",false,true)
	panel(Rect2(1030,270,360,468),PANEL,true)
	var selected: Dictionary=game.selected_item() if game.inspected_source=="stash" else {}
	if selected.is_empty():
		en("ITEM INSPECTOR",1052,310,13,ORANGE)
		txt("选择一件回收物资",1052,376,22,WHITE,true)
		txt("出售后获得对应价值的余额。",1052,418,14,MUTED)
		txt("已解锁的配件会保留在改装库。",1052,450,14,MUTED)
	else:
		var rarity:=clampi(int(selected.get("rarity",0)),0,5)
		tag(ItemsData.RARITY_NAMES[rarity],1052,292,ItemsData.RARITY_COLORS[rarity],92)
		item_icon(selected,Rect2(1132,332,150,122),ItemsData.RARITY_COLORS[rarity])
		txt(selected.name,1052,488,26,WHITE,true)
		txt(str(selected.get("category","回收物资")),1052,519,13,MUTED)
		en("¥ "+money(int(selected.value))+"   /   %.2f kg" % float(selected.weight),1052,560,23,ORANGE)
		var description: String=str(selected.get("description","旧版已结算的物资回收记录。"))
		for n in range(mini(3,ceili(description.length()/22.0))): txt(description.substr(n*22,22),1052,597+n*24,13,MUTED)
		if selected.get("id","")==EquipmentData.EXCHANGE_ITEM:
			button("tab:market",Rect2(1052,630,316,32),"前往兑换六级防具",false,true)
		if not selected.get("settled",false): button("sell",Rect2(1052,670,316,45),"出售  ¥ "+money(int(selected.value)),true,true)
		else: txt("旧版已结算 · 保留回收档案",1052,700,14,MUTED)
	button("tab:deploy",Rect2(1030,778,360,53),"准备下一次行动",true)

func guide() -> void:
	panel(Rect2(0,94,1440,806),INK)
	en("FIELD MANUAL / FIRST DEPLOYMENT",49,151,12,ORANGE)
	txt("带进去，打出来。",46,219,48,WHITE,true)
	txt("目标不是清空地图，而是把有价值的东西带回家。",49,264,19,MUTED)
	var titles:=["01 / 搜索","02 / 交火","03 / 撤离"]
	var body:=[ ["48 处容器含医疗、工具、保险柜等 8 类。","走近朝向容器按 E，逐件搜索并拾取。","背包按格子和负重计算，安全箱保留物资。"], ["开枪会吸引附近的巡逻队。","右键瞄准提升精度，头部命中伤害更高。","利用掩体换弹，按 H 使用采购或回收的药品。"], ["普通行动不检查战备，机密行动需 ¥60,000 战备值。","三至六级分轻重防护，耐久与负面效果不同。","极地典藏咖啡可兑换六级防具，容器概率 0.3%。"] ]
	for i in range(3):
		var x:=49.0+i*454
		panel(Rect2(x,319,431,264),PANEL,true)
		txt(titles[i],x+24,364,25,ORANGE,true)
		for j in range(3): txt(body[i][j],x+24,421+j*40,14,WHITE if j==0 else MUTED)
	rule(49,627,1341)
	txt("基础操作",49,672,20,WHITE,true)
	txt("WASD  移动      Shift  冲刺      Space  跳跃      左键  开火      右键  瞄准      R  换弹",49,720,16,MUTED)
	txt("E  搜索      H  治疗      Tab  背包      M  战术地图      Esc  菜单",49,760,16,MUTED)
	txt("6 人联机 · 真人优先，AI 补位 · 普通 / 机密行动 · 8 把枪 / 6 类改装位 · 本地档案",49,833,14,ORANGE)
