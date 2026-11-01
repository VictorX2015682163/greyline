class_name Items
extends RefCounted

const WeaponModsData = preload("res://scripts/weapon_mods.gd")
const RaidRules = preload("res://scripts/raid_rules.gd")

const RARITY_NAMES := ["普通", "优良", "稀有", "史诗", "传说", "至臻"]
const RARITY_COLORS := [Color("a6b1b3"), Color("79bd91"), Color("77b5e2"), Color("bc94e7"), Color("edc16e"), Color("ee7e73")]
const RARE_EXCHANGE_ID := "polar_coffee"
const RARE_EXCHANGE_CHANCE := 0.003
const CATALOGUE := [
	{"id":"polar_coffee", "name":"极地典藏咖啡", "category":"贵重物品", "rarity":5, "value":96000, "weight":0.25, "w":2, "h":1, "icon":"coffee", "description":"极地科考队密封典藏批次。带回基地后，1 罐兑换任意一件六级甲或六级头并永久解锁。仅危险区保险柜、旅行箱、补给箱及高危军需箱有 0.3% 独立概率出现，无法购买。"},
	{"id":"bolts", "name":"工业螺栓", "category":"工具材料", "rarity":0, "value":650, "weight":0.35, "w":1, "h":1, "icon":"parts", "description":"港区常见的标准紧固件，可用于维修设备。"},
	{"id":"tape", "name":"绝缘胶带", "category":"工具材料", "rarity":0, "value":420, "weight":0.12, "w":1, "h":1, "icon":"parts", "description":"耐潮绝缘胶带，基础电气维护耗材。"},
	{"id":"pliers", "name":"多功能钳", "category":"工具材料", "rarity":1, "value":1800, "weight":0.5, "w":1, "h":2, "icon":"tool", "description":"适用于拆卸与线路维护的折叠工具。"},
	{"id":"drill", "name":"工业电钻", "category":"工具材料", "rarity":2, "value":4800, "weight":1.8, "w":2, "h":2, "icon":"tool", "description":"仓库检修使用的重型电钻，价值不错但十分占空间。"},
	{"id":"bearing", "name":"精密轴承", "category":"工具材料", "rarity":2, "value":3600, "weight":0.65, "w":1, "h":1, "icon":"parts", "description":"密封包装的精密传动组件。"},
	{"id":"battery", "name":"高密度电池", "category":"电子设备", "rarity":1, "value":1600, "weight":0.45, "w":1, "h":2, "icon":"chip", "description":"便携设备供电电池，注意不要挤压。"},
	{"id":"circuit", "name":"精密电路板", "category":"电子设备", "rarity":2, "value":3200, "weight":0.4, "w":2, "h":1, "icon":"chip", "description":"保存完好的工业控制板，有稳定回收需求。"},
	{"id":"cpu", "name":"服务器处理器", "category":"电子设备", "rarity":3, "value":12500, "weight":0.2, "w":1, "h":1, "icon":"chip", "description":"来自控制中心的高性能计算芯片。"},
	{"id":"drive", "name":"加密硬盘", "category":"电子设备", "rarity":4, "value":24800, "weight":0.5, "w":2, "h":1, "icon":"drive", "description":"采用硬件加密的货运数据库存储介质。"},
	{"id":"terminal", "name":"实验数据终端", "category":"电子设备", "rarity":5, "value":86000, "weight":2.4, "w":2, "h":2, "icon":"drive", "description":"封锁前的实验记录终端，是港区最有价值的回收目标之一。"},
	{"id":"lens", "name":"光学组件", "category":"电子设备", "rarity":3, "value":7600, "weight":0.7, "w":2, "h":1, "icon":"optic", "description":"完整的镀膜镜组，可回收用于精密仪器。"},
	{"id":"bandage", "name":"止血绷带", "category":"医疗用品", "rarity":0, "value":380, "weight":0.08, "w":1, "h":1, "icon":"medical", "heal":20, "description":"战局内使用可立即恢复 20 点生命；满血时不会消耗。"},
	{"id":"medkit_field", "name":"野战急救包", "category":"医疗用品", "rarity":2, "value":2400, "weight":0.6, "w":2, "h":1, "icon":"medical", "heal":60, "description":"战局内使用可立即恢复 60 点生命。"},
	{"id":"surgery", "name":"手术器械组", "category":"医疗用品", "rarity":3, "value":9200, "weight":0.9, "w":2, "h":2, "icon":"medical", "description":"完整密封的外科器械组，作为高值医疗物资回收。"},
	{"id":"injector", "name":"应急注射剂", "category":"医疗用品", "rarity":3, "value":6400, "weight":0.1, "w":1, "h":1, "icon":"medical", "heal":40, "description":"战局内使用可恢复 40 点生命。"},
	{"id":"reagent", "name":"实验室试剂", "category":"医疗用品", "rarity":4, "value":19800, "weight":0.4, "w":1, "h":2, "icon":"medical", "description":"需低温保存的稀缺试剂，仅作为物资回收。"},
	{"id":"water", "name":"纯净水", "category":"生活物资", "rarity":0, "value":260, "weight":0.5, "w":1, "h":2, "icon":"supply", "description":"未开封饮用水，可作为生活物资带回。"},
	{"id":"ration", "name":"压缩口粮", "category":"生活物资", "rarity":1, "value":950, "weight":0.4, "w":2, "h":1, "icon":"supply", "description":"长保质期野战食品，港区驻守人员的标准补给。"},
	{"id":"coffee", "name":"精品咖啡豆", "category":"生活物资", "rarity":2, "value":3300, "weight":0.35, "w":1, "h":2, "icon":"supply", "description":"真空包装的进口货物，封锁后价格上涨。"},
	{"id":"watch", "name":"机械腕表", "category":"贵重物品", "rarity":3, "value":14800, "weight":0.15, "w":1, "h":1, "icon":"valuable", "description":"货主遗留的精密机械腕表。"},
	{"id":"gold", "name":"投资金条", "category":"贵重物品", "rarity":4, "value":46000, "weight":1.0, "w":2, "h":1, "icon":"valuable", "description":"带有铸造编号的贵金属条块。"},
	{"id":"sculpture", "name":"鎏金海隼", "category":"贵重物品", "rarity":5, "value":128000, "weight":2.8, "w":2, "h":2, "icon":"valuable", "description":"私人藏品清单中的珍贵雕塑，运输时需要额外空间。"},
	{"id":"documents", "name":"货运清单", "category":"情报文件", "rarity":1, "value":1200, "weight":0.15, "w":1, "h":1, "icon":"document", "description":"记录近期港区货物去向的纸质清单。"},
	{"id":"intel", "name":"机密航运情报", "category":"情报文件", "rarity":4, "value":32000, "weight":0.2, "w":2, "h":1, "icon":"document", "description":"封锁航线与接应人员的加密资料。"},
	{"id":"keycard", "name":"控制室密钥卡", "category":"情报文件", "rarity":3, "value":8800, "weight":0.05, "w":1, "h":1, "icon":"document", "description":"旧控制系统的访问卡，当前作为情报物资回收。"},
	{"id":"ammo", "name":"适配弹药盒", "category":"弹药补给", "rarity":1, "value":900, "weight":0.45, "w":1, "h":1, "icon":"ammo", "ammo":30, "description":"战局内使用可补充当前武器 30 发备弹。"},
	{"id":"ammo_large", "name":"战术弹药箱", "category":"弹药补给", "rarity":2, "value":2700, "weight":1.4, "w":2, "h":2, "icon":"ammo", "ammo":90, "description":"战局内使用可补充当前武器 90 发备弹。"},
]

const CONTAINERS := {
	"military": {"name":"军需箱", "color":"65756a", "time":0.85, "count":4, "hint":"弹药 / 战术配件", "pool":["ammo","ammo_large","bandage","bolts","mod_compensator","mod_suppressor","mod_grip_vertical","mod_grip_angled","mod_red_dot","mod_scope_4x","mod_scope_8x","mod_mag_extended","mod_mag_quick","mod_stock_stable","mod_stock_light","mod_barrel_long","mod_barrel_short"]},
	"medical": {"name":"医疗箱", "color":"b9b7a7", "time":0.7, "count":4, "hint":"医疗 / 实验用品", "pool":["bandage","medkit_field","injector","surgery","reagent"]},
	"toolbox": {"name":"工具箱", "color":"a76e4d", "time":0.65, "count":4, "hint":"工具 / 工业材料", "pool":["bolts","tape","pliers","drill","bearing","battery"]},
	"computer": {"name":"服务器机箱", "color":"476b72", "time":1.15, "count":3, "hint":"电子设备 / 数据", "pool":["circuit","battery","cpu","drive","terminal"]},
	"safe": {"name":"保险柜", "color":"5e6971", "time":1.55, "count":3, "hint":"贵重物品 / 机密情报", "pool":["watch","gold","intel","keycard","sculpture"]},
	"suitcase": {"name":"旅行箱", "color":"78718b", "time":0.8, "count":4, "hint":"生活物资 / 私人物品", "pool":["water","coffee","ration","watch","documents","bandage"]},
	"ration": {"name":"补给箱", "color":"8f8563", "time":0.6, "count":4, "hint":"生活物资 / 应急补给", "pool":["water","ration","coffee","bandage","ammo"]},
	"filing": {"name":"档案柜", "color":"78908b", "time":1.0, "count":3, "hint":"文件 / 密钥 / 情报", "pool":["documents","keycard","intel","drive","circuit"]},
}

static func get_item(id: String) -> Dictionary:
	for item in CATALOGUE:
		if item.id == id: return item.duplicate(true)
	if id.begins_with("mod_"):
		var mod := WeaponModsData.get_mod(id.trim_prefix("mod_"))
		if not mod.is_empty():
			return {"id":id, "name":mod.name, "category":"武器配件", "rarity":int(mod.get("rarity",2)), "value":int(mod.price), "weight":absf(float(mod.weight)), "w":2 if mod.slot in ["muzzle","stock","barrel"] else 1, "h":1, "icon":"attachment", "mod":mod.id, "description":mod.description+"。成功撤离后解锁基地改装使用。"}
	return {}

static func grid_size(item: Dictionary) -> Vector2i:
	return Vector2i(clampi(int(item.get("w",1)),1,6),clampi(int(item.get("h",1)),1,4))

static func pack(items: Array, columns: int, rows: int) -> Array:
	var occupied: Dictionary = {}
	var positions: Array = []
	for item in items:
		var extent := grid_size(item)
		var spot := Vector2i(-1,-1)
		for y in range(rows-extent.y+1):
			for x in range(columns-extent.x+1):
				var fits := true
				for dy in range(extent.y):
					for dx in range(extent.x):
						if occupied.has(Vector2i(x+dx,y+dy)): fits=false
				if fits:
					spot=Vector2i(x,y)
					break
			if spot.x>=0: break
		if spot.x<0:
			# Small connected containers must not lose usable space to insertion order.
			return _pack_small(items,columns,rows) if columns*rows<=9 else []
		positions.append(spot)
		for dy in range(extent.y):
			for dx in range(extent.x): occupied[spot+Vector2i(dx,dy)]=true
	return positions

static func _pack_small(items: Array, columns: int, rows: int) -> Array:
	if columns<=0 or rows<=0 or used_cells(items)>columns*rows: return []
	var order: Array=[]
	var positions: Array=[]
	positions.resize(items.size())
	for i in range(items.size()):
		var extent:=grid_size(items[i])
		if extent.x>columns or extent.y>rows: return []
		order.append({"index":i,"extent":extent,"area":extent.x*extent.y})
	order.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.area>b.area if a.area!=b.area else a.index<b.index)
	return positions if _place_small(order,0,0,columns,rows,positions,{}) else []

static func _place_small(order: Array, depth: int, occupied: int, columns: int, rows: int, positions: Array, failed: Dictionary) -> bool:
	if depth==order.size(): return true
	var state:=Vector2i(depth,occupied)
	if failed.has(state): return false
	var extent: Vector2i=order[depth].extent
	for y in range(rows-extent.y+1):
		for x in range(columns-extent.x+1):
			var mask:=0
			for dy in range(extent.y):
				for dx in range(extent.x): mask|=1<<((y+dy)*columns+x+dx)
			if occupied&mask: continue
			positions[int(order[depth].index)]=Vector2i(x,y)
			if _place_small(order,depth+1,occupied|mask,columns,rows,positions,failed): return true
	failed[state]=true
	return false

static func used_cells(items: Array) -> int:
	var total := 0
	for item in items:
		var extent := grid_size(item)
		total+=extent.x*extent.y
	return total

static func rare_exchange_chance(kind: String, tier: int) -> float:
	return RARE_EXCHANGE_CHANCE if (tier>=1 and kind in ["safe","suitcase","ration"]) or (tier>=2 and kind=="military") else 0.0

static func roll_container(kind: String, tier: int, rng: RandomNumberGenerator, mode: String="普通") -> Array:
	var profile: Dictionary=CONTAINERS[kind]
	var result: Array=[]
	var count:=rng.randi_range(3 if mode=="机密" else 2,int(profile.count))
	var candidates: Array=[]
	for id in profile.pool:
		var item:=get_item(id)
		if int(item.rarity)<=RaidRules.loot_quality_cap(mode,tier):
			for n in range(RaidRules.loot_weight(mode,int(item.rarity))): candidates.append(item)
	for i in range(count):
		result.append(candidates[rng.randi_range(0,candidates.size()-1)].duplicate(true))
	# Exactly one independent roll per eligible container, outside all normal pools.
	if rng.randf()<rare_exchange_chance(kind,tier):
		result[rng.randi_range(0,result.size()-1)]=get_item(RARE_EXCHANGE_ID)
	return result
