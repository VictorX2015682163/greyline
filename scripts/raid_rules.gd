extends RefCounted
## Shared rules are selected before a raid is generated, on every peer.

static func guard(mode: String, elite: bool) -> Dictionary:
	var classified:=mode=="机密"
	return {
		"health":(140.0 if elite else 100.0)*(1.25 if classified else 1.0),
		"sight":(48.0 if elite else 38.0)+(10.0 if classified else 0.0),
		"reaction":Vector2(0.22,0.5) if classified else Vector2(0.35,0.85),
		"decision":Vector2(0.4,0.7) if classified else Vector2(0.65,1.1),
		"interval":(Vector2(0.4,0.8) if elite else Vector2(0.6,1.15))*(0.8 if classified else 1.0),
		"damage":(Vector2(10,16) if elite else Vector2(7,13))*(1.2 if classified else 1.0),
		"accuracy_bonus":0.1 if classified else 0.0,
		"accuracy_cap":0.72 if classified else 0.6,
		"combat_range":50.0 if classified else 40.0,
		"pursuit_speed":3.5 if classified else 3.1,
	}

static func is_elite(mode: String, index: int) -> bool:
	return index in ([3,5,7,8,9,10] if mode=="机密" else [5,8,9])

static func bot(mode: String) -> Dictionary:
	var classified:=mode=="机密"
	return {
		"scan":Vector2(0.09,0.18) if classified else Vector2(0.13,0.26),
		"decision":Vector2(0.3,0.65) if classified else Vector2(0.45,0.95),
		"reaction":Vector2(0.18,0.42) if classified else Vector2(0.28,0.85),
		"sight":75.0 if classified else 65.0,
		"aim_base":0.011 if classified else 0.018,
		"aim_distance":0.0005 if classified else 0.0008,
		"turn":Vector2(2.7,4.0) if classified else Vector2(2.0,3.3),
		"pitch_speed":2.3 if classified else 1.7,
		"burst":Vector2(0.28,0.65) if classified else Vector2(0.18,0.55),
		"pause":Vector2(0.18,0.5) if classified else Vector2(0.28,0.85),
	}

static func loot_weight(mode: String, rarity: int) -> int:
	if mode=="机密": return 3 if rarity>=4 else (6 if rarity>=2 else 4)
	return 1 if rarity>=4 else 4

static func loot_quality_cap(mode: String, tier: int) -> int:
	return mini(5,tier+(4 if mode=="机密" else 3))
