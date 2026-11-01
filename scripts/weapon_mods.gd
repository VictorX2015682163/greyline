class_name WeaponMods
extends RefCounted

const SLOTS := ["optic", "muzzle", "grip", "magazine", "stock", "barrel"]
const SLOT_NAMES := {"optic":"瞄具", "muzzle":"枪口", "grip":"握把", "magazine":"弹匣", "stock":"枪托", "barrel":"枪管"}
const CATALOGUE := [
	{"id":"red_dot", "name":"全息红点瞄具", "slot":"optic", "price":1800, "weight":0.12, "rarity":2, "aim_fov":49.0, "spread":0.9, "description":"1 倍快速瞄具 · 瞄准视野 49° · 散布 -10%", "compatible":[0,1,2,3,4,5,6,7]},
	{"id":"scope_4x", "name":"4 倍战术瞄准镜", "slot":"optic", "price":4200, "weight":0.38, "rarity":3, "aim_fov":26.0, "spread":0.78, "description":"4 倍观察视野 · 散布 -22% · 增加重量", "compatible":[0,1,5,6,7]},
	{"id":"scope_8x", "name":"8 倍精密瞄准镜", "slot":"optic", "price":6800, "weight":0.65, "rarity":4, "aim_fov":16.0, "spread":0.68, "description":"8 倍远距视野 · 散布 -32% · 适配精确平台", "compatible":[6,7]},
	{"id":"compensator", "name":"制退补偿器", "slot":"muzzle", "price":2200, "weight":0.16, "rarity":2, "recoil":0.77, "description":"后坐力 -23% · 枪声传播距离不变", "compatible":[0,1,2,3,5,6]},
	{"id":"suppressor", "name":"战术消音器", "slot":"muzzle", "price":5800, "weight":0.46, "rarity":3, "recoil":0.9, "noise_radius":20.0, "description":"枪声警戒半径降至 20 m · 后坐力 -10%", "compatible":[0,1,2,3,6,7]},
	{"id":"grip_vertical", "name":"垂直战术握把", "slot":"grip", "price":1600, "weight":0.14, "rarity":2, "recoil":0.84, "spread":0.94, "description":"后坐力 -16% · 散布 -6%", "compatible":[0,1,2,3,5,6]},
	{"id":"grip_angled", "name":"轻量斜角握把", "slot":"grip", "price":2000, "weight":0.08, "rarity":2, "recoil":0.94, "spread":0.82, "description":"散布 -18% · 后坐力 -6% · 更轻", "compatible":[0,1,2,3,5,6]},
	{"id":"mag_extended", "name":"扩容供弹组件", "slot":"magazine", "price":3200, "weight":0.35, "rarity":3, "magazine":1.5, "reload":1.14, "description":"弹容 +50%（向下取整）· 换弹时间 +14%", "compatible":[0,1,2,3,4,6,7]},
	{"id":"mag_quick", "name":"快速供弹组件", "slot":"magazine", "price":2400, "weight":0.1, "rarity":2, "reload":0.8, "description":"换弹时间 -20% · 保留原始弹容", "compatible":[0,1,2,3,5,6,7]},
	{"id":"stock_stable", "name":"稳固战术枪托", "slot":"stock", "price":2600, "weight":0.3, "rarity":2, "recoil":0.85, "description":"后坐力 -15% · 较重枪托降低机动", "compatible":[0,1,2,3,4,5,6,7]},
	{"id":"stock_light", "name":"轻量骨架枪托", "slot":"stock", "price":2100, "weight":-0.25, "rarity":2, "recoil":1.08, "description":"整枪重量 -0.25 kg · 后坐力 +8%", "compatible":[0,1,2,3,4,6,7]},
	{"id":"barrel_long", "name":"精密加长枪管", "slot":"barrel", "price":3800, "weight":0.5, "rarity":3, "range":1.25, "spread":0.8, "description":"有效射程 +25% · 散布 -20% · 更重", "compatible":[0,1,4,5,6,7]},
	{"id":"barrel_short", "name":"轻量短枪管", "slot":"barrel", "price":1800, "weight":-0.3, "rarity":2, "range":0.85, "spread":1.12, "description":"整枪重量 -0.3 kg · 射程 -15% · 散布 +12%", "compatible":[0,1,2,3]},
]

static func get_mod(id: String) -> Dictionary:
	for mod in CATALOGUE:
		if mod.id==id: return mod
	return {}

static func options(index: int, slot: String) -> Array:
	var result: Array=[]
	for mod in CATALOGUE:
		if mod.slot==slot and index in mod.compatible: result.append(mod)
	return result

static func sanitize(index: int, build: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for slot in SLOTS:
		var mod:=get_mod(str(build.get(slot,"")))
		if not mod.is_empty() and mod.slot==slot and index in mod.compatible: result[slot]=mod.id
	return result

static func weapon(index: int, build: Dictionary) -> Dictionary:
	var result:=Arsenal.get_weapon(index).duplicate(true)
	result["aim_fov"]=22.0 if index==7 else (36.0 if index==6 else 51.0)
	result["noise_radius"]=42.0
	result["mod_count"]=0
	if index<0:
		result.aim_fov=78.0
		result.noise_radius=0.0
		return result
	for id in sanitize(index,build).values():
		var mod:=get_mod(str(id))
		result.weight=float(result.weight)+float(mod.weight)
		result.value=int(result.get("value",result.price))+int(mod.price)
		result.mod_count+=1
		for key in ["recoil","spread","reload","range","magazine"]:
			if mod.has(key): result[key]=float(result[key])*float(mod[key])
		for key in ["aim_fov","noise_radius"]:
			if mod.has(key): result[key]=mod[key]
	result.magazine=int(result.magazine)
	return result
