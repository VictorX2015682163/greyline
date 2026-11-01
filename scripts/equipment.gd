class_name Equipment
extends RefCounted

## Body and head protection are independent. Tier 6 is redeemed, never bought.
const EXCHANGE_ITEM := "polar_coffee"
const LEGACY_REFUNDS := {"armor_light":3800,"armor_heavy":9000,"helmet_fast":1800,"helmet_heavy":4800,"backpack_light":1600,"backpack_tactical":4800,"rig_basic":1400,"rig_assault":4200}
const GEAR := [
	{"id":"armor_1","slot":"armor","tier":1,"variant":"basic","name":"一级甲","short":"一级甲","price":2800,"value":2800,"weight":3.5,"armor":45,"reduction":0.35,"speed_penalty":0.02,"stamina_penalty":0.03,"aim_penalty":0.02,"hearing":1.0,"purchasable":true,"description":"标准防弹衣，提供基础躯干防护。"},
	{"id":"armor_2","slot":"armor","tier":2,"variant":"basic","name":"二级甲","short":"二级甲","price":6200,"value":6200,"weight":4.2,"armor":60,"reduction":0.45,"speed_penalty":0.04,"stamina_penalty":0.06,"aim_penalty":0.04,"hearing":1.0,"purchasable":true,"description":"标准防弹衣，提供基础躯干防护。"},
	{"id":"armor_3_durable","slot":"armor","tier":3,"variant":"durable","name":"三级耐久甲","short":"三级耐久甲","price":14500,"value":14500,"weight":7.2,"armor":100,"reduction":0.62,"speed_penalty":0.12,"stamina_penalty":0.2,"aim_penalty":0.16,"hearing":1.0,"purchasable":true,"description":"同级最高躯干防护与耐久，移动、体力和开镜代价高。"},
	{"id":"armor_3_light","slot":"armor","tier":3,"variant":"light","name":"三级轻甲","short":"三级轻甲","price":12000,"value":12000,"weight":3.8,"armor":68,"reduction":0.52,"speed_penalty":0.025,"stamina_penalty":0.04,"aim_penalty":0.025,"hearing":1.0,"purchasable":true,"description":"轻量插板保留机动能力，防护和耐久低于同级耐久甲。"},
	{"id":"armor_4_durable","slot":"armor","tier":4,"variant":"durable","name":"四级耐久甲","short":"四级耐久甲","price":28000,"value":28000,"weight":8.3,"armor":125,"reduction":0.72,"speed_penalty":0.14,"stamina_penalty":0.24,"aim_penalty":0.2,"hearing":1.0,"purchasable":true,"description":"同级最高躯干防护与耐久，移动、体力和开镜代价高。"},
	{"id":"armor_4_light","slot":"armor","tier":4,"variant":"light","name":"四级轻甲","short":"四级轻甲","price":24000,"value":24000,"weight":4.15,"armor":82,"reduction":0.62,"speed_penalty":0.03,"stamina_penalty":0.05,"aim_penalty":0.03,"hearing":1.0,"purchasable":true,"description":"轻量插板保留机动能力，防护和耐久低于同级耐久甲。"},
	{"id":"armor_5_durable","slot":"armor","tier":5,"variant":"durable","name":"五级耐久甲","short":"五级耐久甲","price":54000,"value":54000,"weight":9.4,"armor":150,"reduction":0.82,"speed_penalty":0.16,"stamina_penalty":0.28,"aim_penalty":0.24,"hearing":1.0,"purchasable":true,"description":"同级最高躯干防护与耐久，移动、体力和开镜代价高。"},
	{"id":"armor_5_light","slot":"armor","tier":5,"variant":"light","name":"五级轻甲","short":"五级轻甲","price":47000,"value":47000,"weight":4.5,"armor":96,"reduction":0.72,"speed_penalty":0.035,"stamina_penalty":0.06,"aim_penalty":0.035,"hearing":1.0,"purchasable":true,"description":"轻量插板保留机动能力，防护和耐久低于同级耐久甲。"},
	{"id":"armor_6_durable","slot":"armor","tier":6,"variant":"durable","name":"六级耐久甲","short":"六级耐久甲","price":0,"value":125000,"weight":10.5,"armor":175,"reduction":0.91,"speed_penalty":0.18,"stamina_penalty":0.32,"aim_penalty":0.28,"hearing":1.0,"purchasable":false,"description":"同级最高躯干防护与耐久，移动、体力和开镜代价高。"},
	{"id":"armor_6_light","slot":"armor","tier":6,"variant":"light","name":"六级轻甲","short":"六级轻甲","price":0,"value":110000,"weight":4.85,"armor":110,"reduction":0.82,"speed_penalty":0.04,"stamina_penalty":0.07,"aim_penalty":0.04,"hearing":1.0,"purchasable":false,"description":"轻量插板保留机动能力，防护和耐久低于同级耐久甲。"},
	{"id":"helmet_1","slot":"helmet","tier":1,"variant":"basic","name":"一级头","short":"一级头","price":1400,"value":1400,"weight":1.1,"armor":28,"reduction":0.30,"speed_penalty":0.005,"stamina_penalty":0.01,"aim_penalty":0.01,"hearing":1.0,"purchasable":true,"description":"标准头部防护，单独承受头部命中伤害。"},
	{"id":"helmet_2","slot":"helmet","tier":2,"variant":"basic","name":"二级头","short":"二级头","price":2800,"value":2800,"weight":1.3,"armor":38,"reduction":0.4,"speed_penalty":0.01,"stamina_penalty":0.02,"aim_penalty":0.02,"hearing":0.98,"purchasable":true,"description":"标准头部防护，单独承受头部命中伤害。"},
	{"id":"helmet_3_heavy","slot":"helmet","tier":3,"variant":"heavy","name":"三级重头","short":"三级重头","price":7800,"value":7800,"weight":2.4,"armor":75,"reduction":0.6,"speed_penalty":0.045,"stamina_penalty":0.08,"aim_penalty":0.1,"hearing":0.72,"purchasable":true,"description":"同级最高头部防护，封闭护耳压缩听觉范围，机动与开镜代价高。"},
	{"id":"helmet_3_hearing","slot":"helmet","tier":3,"variant":"hearing","name":"三级听力头","short":"三级听力头","price":8500,"value":8500,"weight":1.15,"armor":45,"reduction":0.46,"speed_penalty":0.003,"stamina_penalty":0.01,"aim_penalty":0.01,"hearing":1.2,"purchasable":true,"description":"主动拾音扩大枪声与脚步感知范围，负面效果少，头部防护较低。"},
	{"id":"helmet_4_heavy","slot":"helmet","tier":4,"variant":"heavy","name":"四级重头","short":"四级重头","price":16000,"value":16000,"weight":2.8,"armor":92,"reduction":0.7,"speed_penalty":0.06,"stamina_penalty":0.11,"aim_penalty":0.13,"hearing":0.66,"purchasable":true,"description":"同级最高头部防护，封闭护耳压缩听觉范围，机动与开镜代价高。"},
	{"id":"helmet_4_hearing","slot":"helmet","tier":4,"variant":"hearing","name":"四级听力头","short":"四级听力头","price":17500,"value":17500,"weight":1.25,"armor":55,"reduction":0.56,"speed_penalty":0.004,"stamina_penalty":0.013,"aim_penalty":0.013,"hearing":1.28,"purchasable":true,"description":"主动拾音扩大枪声与脚步感知范围，负面效果少，头部防护较低。"},
	{"id":"helmet_5_heavy","slot":"helmet","tier":5,"variant":"heavy","name":"五级重头","short":"五级重头","price":31000,"value":31000,"weight":3.2,"armor":109,"reduction":0.8,"speed_penalty":0.075,"stamina_penalty":0.14,"aim_penalty":0.16,"hearing":0.6,"purchasable":true,"description":"同级最高头部防护，封闭护耳压缩听觉范围，机动与开镜代价高。"},
	{"id":"helmet_5_hearing","slot":"helmet","tier":5,"variant":"hearing","name":"五级听力头","short":"五级听力头","price":34000,"value":34000,"weight":1.35,"armor":65,"reduction":0.66,"speed_penalty":0.005,"stamina_penalty":0.016,"aim_penalty":0.016,"hearing":1.36,"purchasable":true,"description":"主动拾音扩大枪声与脚步感知范围，负面效果少，头部防护较低。"},
	{"id":"helmet_6_heavy","slot":"helmet","tier":6,"variant":"heavy","name":"六级重头","short":"六级重头","price":0,"value":85000,"weight":3.6,"armor":126,"reduction":0.9,"speed_penalty":0.09,"stamina_penalty":0.17,"aim_penalty":0.19,"hearing":0.54,"purchasable":false,"description":"同级最高头部防护，封闭护耳压缩听觉范围，机动与开镜代价高。"},
	{"id":"helmet_6_hearing","slot":"helmet","tier":6,"variant":"hearing","name":"六级听力头","short":"六级听力头","price":0,"value":90000,"weight":1.45,"armor":75,"reduction":0.76,"speed_penalty":0.006,"stamina_penalty":0.019,"aim_penalty":0.019,"hearing":1.44,"purchasable":false,"description":"主动拾音扩大枪声与脚步感知范围，负面效果少，头部防护较低。"},
]

const CONSUMABLES := [
	{"id":"ammo_pack", "slot":"ammo", "name":"通用弹药包", "short":"弹药", "unit_price":900, "value":900, "units":120, "weight":2.0, "description":"补充 120 发通用训练弹药，口径由枪械自动匹配。"},
	{"id":"medkit", "slot":"meds", "name":"战地急救包", "short":"急救包", "unit_price":450, "value":450, "units":1, "weight":0.6, "description":"一枚可在战局中使用的急救包。"},
]

static func gear_item(id: String) -> Dictionary:
	for item in GEAR:
		if item.id == id: return item
	for item in CONSUMABLES:
		if item.id == id: return item
	return {}

static func gear_for_slot(slot: String) -> Array:
	var result: Array = []
	for item in GEAR:
		if item.slot == slot: result.append(item)
	return result

static func all_gear() -> Array:
	return GEAR.duplicate(true)

static func all_consumables() -> Array:
	return CONSUMABLES.duplicate(true)
