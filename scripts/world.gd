class_name RaidWorld
extends Node3D

const ItemsData = preload("res://scripts/items.gd")
const RaidRules = preload("res://scripts/raid_rules.gd")

const MAP_SIZE := Vector2(220, 200)
const EXITS := [Vector3(88, 0, 80), Vector3(-91, 0, -82)]
const EXIT_NAMES := ["南堤接应点", "北侧检修门"]
var mats: Dictionary = {}
var solids: Array[Rect2] = []
var map_shapes: Array = []
var loot: Array[Node3D] = []
var enemies: Array = []
var navigation := AStarGrid2D.new()
var rng := RandomNumberGenerator.new()
var water: MeshInstance3D
var elapsed := 0.0
var loot_rng := RandomNumberGenerator.new()
var raid_mode := "普通"

func _ready() -> void:
	rng.seed = 924071
	loot_rng.randomize()
	make_materials()
	build_environment()
	build_map()
	build_navigation()

func make_materials() -> void:
	var colors := {"ground":"565a51", "concrete":"8c9287", "dark":"333f42", "road":"394246", "line":"d6bb76", "rust":"86583f", "blue":"476b72", "green":"65756a", "ivory":"b4b5a5", "black":"222e31", "yellow":"dba950", "red":"a0614b"}
	for key in colors:
		mats[key] = Arsenal.material(Color(colors[key]), 0.25 if key in ["blue", "green", "rust"] else 0.0)
	# Hard-surface material response: dull concrete, oxidized steel and
	# restrained warning paint keep the port grounded and readable.
	(mats["concrete"] as StandardMaterial3D).roughness=0.92
	(mats["ivory"] as StandardMaterial3D).roughness=0.86
	(mats["road"] as StandardMaterial3D).roughness=0.98
	(mats["ground"] as StandardMaterial3D).roughness=1.0
	(mats["dark"] as StandardMaterial3D).metallic=0.72
	(mats["dark"] as StandardMaterial3D).roughness=0.46
	(mats["black"] as StandardMaterial3D).metallic=0.5
	(mats["black"] as StandardMaterial3D).roughness=0.54
	(mats["rust"] as StandardMaterial3D).metallic=0.34
	(mats["rust"] as StandardMaterial3D).roughness=0.82
	(mats["blue"] as StandardMaterial3D).roughness=0.62
	(mats["green"] as StandardMaterial3D).roughness=0.78
	(mats["yellow"] as StandardMaterial3D).roughness=0.74
	var glow := Arsenal.material(Color("92d7a3"))
	glow.emission_enabled = true
	glow.emission = Color("6bcf97")
	glow.emission_energy_multiplier = 1.3
	mats["glow"] = glow
	var ground_shader := Shader.new()
	ground_shader.code = "shader_type spatial; varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){float n=fract(sin(dot(floor(wp.xz*3.0),vec2(12.9898,78.233)))*43758.5453); ALBEDO=mix(vec3(0.09,0.115,0.105),vec3(0.13,0.15,0.135),n*0.65); ROUGHNESS=1.0;}"
	var ground_mat := ShaderMaterial.new()
	ground_mat.shader = ground_shader
	mats["ground"] = ground_mat

func build_environment() -> void:
	var env := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("26333b")
	sky_material.sky_horizon_color = Color("778084")
	sky_material.ground_horizon_color = Color("545b5c")
	sky_material.ground_bottom_color = Color("20272b")
	sky_material.sky_curve = 0.22
	sky.sky_material = sky_material
	settings.sky = sky
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("9aa7ad")
	settings.ambient_light_energy = 0.28
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.adjustment_enabled = true
	settings.adjustment_brightness = 0.92
	settings.adjustment_contrast = 1.18
	settings.adjustment_saturation = 0.72
	settings.fog_enabled = true
	settings.fog_light_color = Color("657074")
	settings.fog_density = 0.0023
	env.environment = settings
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32, -28, 0)
	sun.light_color = Color("d6d0bd")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 170
	add_child(sun)

func block(pos: Vector3, size: Vector3, material_key: String, collision: bool = true, on_map: bool = false) -> MeshInstance3D:
	var mesh := Arsenal.box(self, size, pos, mats[material_key])
	if collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
		mesh.add_child(body)
		if pos.y - size.y / 2 < 1.8 and pos.y + size.y / 2 > 0.15:
			solids.append(Rect2(pos.x - size.x / 2 - 0.5, pos.z - size.z / 2 - 0.5, size.x + 1, size.z + 1))
	if on_map:
		map_shapes.append({"rect":Rect2(pos.x - size.x / 2, pos.z - size.z / 2, size.x, size.z), "color":material_key})
	return mesh

func vertical_cylinder(pos: Vector3, radius: float, height: float, key: String, collision: bool = false) -> MeshInstance3D:
	var mesh := Arsenal.cylinder(self, radius, height, pos, mats[key])
	mesh.rotation.x = 0
	if collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = radius
		cylinder.height = height
		shape.shape = cylinder
		body.add_child(shape)
		mesh.add_child(body)
		solids.append(Rect2(pos.x - radius - 0.6, pos.z - radius - 0.6, radius * 2 + 1.2, radius * 2 + 1.2))
		map_shapes.append({"rect":Rect2(pos.x - radius, pos.z - radius, radius * 2, radius * 2), "color":key})
	return mesh

func sign_at(text: String, pos: Vector3, font_size: int = 64, angle: float = 0.0, color: Color = Color("e5e7d9")) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.016
	label.position = pos
	label.rotation.y = angle
	label.modulate = color
	label.outline_size = 3
	add_child(label)

func container_at(pos: Vector3, key: String, stacked: bool = false) -> void:
	var h := 2.8
	block(pos + Vector3(0, h / 2, 0), Vector3(4.5, h, 11.5), key, true, true)
	for side in [-1, 1]:
		for i in range(10):
			block(pos + Vector3(side * 2.28, 1.4, -5.2 + i * 1.14), Vector3(0.055, 2.55, 0.09), "dark", false)
		block(pos + Vector3(side * 1.1, 1.4, 5.78), Vector3(0.045, 2.5, 0.05), "ivory", false)
	block(pos + Vector3(0, 2.81, 0), Vector3(4.6, 0.08, 11.6), "dark", false)
	if stacked:
		container_at(pos + Vector3(0, 2.9, 0), "ivory" if key != "ivory" else "rust")

func warehouse(pos: Vector3, width: float, depth: float, code: String) -> void:
	block(pos + Vector3(0, 0.07, 0), Vector3(width, 0.14, depth), "concrete", false, true)
	block(pos + Vector3(-width/2, 3, 0), Vector3(0.45, 6, depth), "ivory")
	block(pos + Vector3(width/2, 3, 0), Vector3(0.45, 6, depth), "ivory")
	for side in [-1, 1]:
		block(pos + Vector3(-width/2 + 3, 2.5, side * depth/2), Vector3(6, 5, 0.45), "ivory")
		block(pos + Vector3(width/2 - 3, 2.5, side * depth/2), Vector3(6, 5, 0.45), "ivory")
		block(pos + Vector3(0, 5.5, side * depth/2), Vector3(width, 1, 0.45), "dark")
		for x in [-width/2, width/2]:
			block(pos + Vector3(x, 3.4, side * depth/2), Vector3(0.7, 7, 0.7), "rust")
	block(pos + Vector3(0, 6.2, 0), Vector3(width + 1, 0.22, depth + 1), "dark")
	for z in [-depth/2 + 4, 0, depth/2 - 4]:
		for x in [-width/2 + 2.3, width/2 - 2.3]:
			block(pos + Vector3(x, 1.1, z), Vector3(3, 2.2, 3.6), "rust", true, true)
	sign_at(code, pos + Vector3(0, 5.4, depth/2 + 0.3), 84)

func build_map() -> void:
	block(Vector3(0, -0.3, 0), Vector3(224, 0.6, 204), "ground")
	block(Vector3(0, 0.015, 45), Vector3(216, 0.025, 12), "road", false)
	block(Vector3(24, 0.02, -5), Vector3(12, 0.025, 192), "road", false)
	block(Vector3(-59, 0.02, -62), Vector3(86, 0.025, 10), "road", false)
	for z in range(-94, 96, 9):
		block(Vector3(24, 0.045, z), Vector3(0.2, 0.025, 3.8), "line", false)
	for x in range(-100, 104, 9):
		block(Vector3(x, 0.045, 45), Vector3(3.8, 0.025, 0.2), "line", false)
	# Perimeter and sea wall. Every playable area remains inside the boundary.
	for x in [-111, 111]:
		block(Vector3(x, 1.5, 0), Vector3(1, 3, 204), "concrete")
	for z in [-101, 101]:
		block(Vector3(0, 1.5, z), Vector3(224, 3, 1), "concrete")
	water = block(Vector3(160, -1.1, 0), Vector3(95, 0.15, 430), "blue", false)
	water.material_override = Arsenal.material(Color("426b73"), 0.65)
	for i in range(16):
		block(Vector3(116 + rng.randf_range(0, 70), -0.95, rng.randf_range(-180, 180)), Vector3(rng.randf_range(8, 24), 0.025, 0.18), "ivory", false)
	# A / administration: open ground floor, readable facade and sheltered yard.
	warehouse(Vector3(-71, 0, -37), 25, 24, "A / CUSTOMS")
	block(Vector3(-71, 7.6, -37), Vector3(26, 2.5, 25), "concrete", false)
	for x in range(-80, -60, 4):
		block(Vector3(x, 7.6, -24.35), Vector3(2.5, 1.3, 0.1), "blue", false)
	block(Vector3(-71, 9.2, -37), Vector3(27, 0.25, 26), "dark", false)
	# B / central depot: two entrances and crate cover.
	warehouse(Vector3(-8, 0, -15), 29, 36, "B / TRANSIT 04")
	# C / container maze: parallel lanes with cross routes.
	var container_positions := [Vector3(-82,0,12), Vector3(-65,0,10), Vector3(-47,0,12), Vector3(-82,0,29), Vector3(-47,0,29), Vector3(-44,0,-17), Vector3(1,0,18), Vector3(11,0,70), Vector3(-8,0,73), Vector3(-29,0,73), Vector3(-48,0,73), Vector3(-50,0,-83), Vector3(-31,0,-83)]
	for i in range(container_positions.size()):
		container_at(container_positions[i], ["blue", "rust", "green"][i % 3], i in [0, 2, 9, 11])
	# D / refinery: cylindrical silhouettes and broken sight lines.
	for x in [55, 83]:
		for z in [-57, -27]:
			vertical_cylinder(Vector3(x, 5, z), 8.5, 10, "ivory", true)
			vertical_cylinder(Vector3(x, 10.1, z), 8.8, 0.25, "dark")
			vertical_cylinder(Vector3(x, 0.3, z), 9.4, 0.6, "concrete")
			for angle in range(0, 360, 45):
				var a := deg_to_rad(float(angle))
				block(Vector3(x + cos(a)*8.8, 10.7, z + sin(a)*8.8), Vector3(0.06, 1.2, 0.06), "yellow", false)
	for z in [-72, -42, -12]:
		var pipe := Arsenal.cylinder(self, 0.35, 50, Vector3(70, 3.4, z), mats.rust)
		pipe.rotation = Vector3(0, 0, PI/2)
		for x in [45, 95]:
			block(Vector3(x, 1.7, z), Vector3(0.35, 3.4, 0.35), "dark")
	warehouse(Vector3(67, 0, 16), 24, 20, "D / CONTROL")
	# Port crane: large landmark visible throughout the map.
	for x in [87, 103]:
		for z in [42, 59]:
			block(Vector3(x, 12, z), Vector3(1.2, 24, 1.2), "yellow")
	block(Vector3(95, 25, 50), Vector3(20, 2, 22), "yellow", false)
	block(Vector3(95, 30, 25), Vector3(1.5, 1.4, 76), "yellow", false)
	block(Vector3(95, 27, 43), Vector3(3, 3, 4), "dark", false)
	for z in range(-9, 62, 7):
		block(Vector3(95, 30.9, z), Vector3(1.4, 0.15, 0.15), "dark", false)
	block(Vector3(95, 20, 0), Vector3(0.07, 20, 0.07), "black", false)
	# Checkpoint, roadblocks, pallets, drums and sparse vegetation.
	for pos in [Vector3(-71,0,60), Vector3(-32,0,38), Vector3(36,0,38), Vector3(39,0,-78), Vector3(1,0,-62), Vector3(64,0,64), Vector3(-95,0,-67)]:
		block(pos + Vector3(0,0.65,0), Vector3(7,1.3,0.8), "concrete", true, true)
		for i in range(5):
			block(pos + Vector3(-2.5+i*1.2,0.7,0.42), Vector3(0.5,0.45,0.03), "yellow", false)
	for pos in [Vector3(-12,0,3),Vector3(3,0,-27),Vector3(-75,0,-37),Vector3(-65,0,-44),Vector3(63,0,18),Vector3(73,0,10),Vector3(44,0,6),Vector3(-94,0,45)]:
		block(pos + Vector3(0,0.6,0),Vector3(2,1.2,2),"rust",true,true)
		block(pos + Vector3(0,1.23,0),Vector3(2.1,0.08,2.1),"dark",false)
	for i in range(32):
		var p := Vector3(rng.randf_range(-105,105),0,rng.randf_range(-96,96))
		if absf(p.x - 24) < 10 or absf(p.z - 45) < 9: continue
		vertical_cylinder(p + Vector3(0,0.45,0),0.33,0.9,"rust",false)
	for i in range(22):
		var x := -105.0 + rng.randf_range(0,8)
		var z := rng.randf_range(-94,94)
		block(Vector3(x,0.3,z),Vector3(1.8,0.6,2),"green",false)
	# Extraction pads.
	for i in range(2):
		var pos: Vector3 = EXITS[i]
		block(pos + Vector3(0,0.04,0),Vector3(13,0.07,13),"dark",false)
		for side in [-1,1]:
			block(pos + Vector3(side*6,0.1,0),Vector3(0.18,0.04,12),"yellow",false)
			block(pos + Vector3(0,0.1,side*6),Vector3(12,0.04,0.18),"yellow",false)
		vertical_cylinder(pos + Vector3(4,0.45,4),0.12,0.9,"glow")
		sign_at("EXFIL / 0" + str(i+1),pos + Vector3(0,2,-5),44,0,Color("a1ddaf"))
	# Fixed container positions and themed pools; contents roll independently each raid.
	var loot_positions := [Vector3(-74,0,76),Vector3(-90,0,6),Vector3(-63,0,23),Vector3(-35,0,19),Vector3(-76,0,-34),Vector3(-66,0,-46),Vector3(-87,0,-50),Vector3(-43,0,-73),Vector3(-5,0,-3),Vector3(0,0,-26),Vector3(-13,0,-23),Vector3(7,0,-12),Vector3(45,0,-60),Vector3(70,0,-44),Vector3(94,0,-24),Vector3(64,0,20),Vector3(73,0,11),Vector3(48,0,12),Vector3(56,0,69),Vector3(-15,0,62),Vector3(4,0,83),Vector3(82,0,-78)]
	for i in range(loot_positions.size()):
		var tier := 0 if i < 4 or i == 19 or i == 20 else (2 if i in [9,13,16,21] else 1)
		add_loot(loot_positions[i],tier,i, ["military","toolbox","suitcase","ration","medical","filing","safe","toolbox","military","computer","computer","military","toolbox","computer","safe","medical","filing","military","ration","ration","suitcase","safe"][i])
	var extra_positions := [Vector3(-79,0,81),Vector3(-68,0,67),Vector3(-91,0,27),Vector3(-74,0,20),Vector3(-56,0,3),Vector3(-37,0,31),Vector3(-69,0,-30),Vector3(-73,0,-44),Vector3(-60,0,-38),Vector3(-92,0,-42),Vector3(-76,0,-64),Vector3(-35,0,-64),Vector3(-17,0,-8),Vector3(-8,0,-29),Vector3(2,0,-18),Vector3(-10,0,-43),Vector3(41,0,-48),Vector3(70,0,-64),Vector3(98,0,-43),Vector3(58,0,12),Vector3(69,0,23),Vector3(78,0,19),Vector3(47,0,68),Vector3(30,0,80),Vector3(-22,0,57),Vector3(90,0,-86)]
	var kinds := ["medical","toolbox","suitcase","ration","military","toolbox","filing","safe","medical","suitcase","filing","military","toolbox","computer","military","safe","toolbox","computer","safe","computer","medical","filing","ration","suitcase","ration","safe"]
	for i in range(extra_positions.size()):
		add_loot(extra_positions[i],2 if extra_positions[i].x>35 else 1,i+22,kinds[i])
	# Enemy placements avoid the player's insertion zone.
	var enemy_positions := [Vector3(-60,0,9),Vector3(-83,0,-19),Vector3(-61,0,-51),Vector3(-30,0,-31),Vector3(-5,0,-9),Vector3(5,0,-29),Vector3(37,0,-4),Vector3(70,0,-10),Vector3(66,0,-42),Vector3(94,0,-66),Vector3(62,0,25),Vector3(46,0,66),Vector3(6,0,61),Vector3(-32,0,-72)]
	for i in range(enemy_positions.size()):
		var enemy := RaidEnemy.new()
		enemy.position = enemy_positions[i] + Vector3.UP * 0.15
		enemy.home = enemy_positions[i]
		enemy.world = self
		enemy.elite = RaidRules.is_elite(raid_mode,i)
		add_child(enemy)
		enemies.append(enemy)

func add_loot(pos: Vector3, tier: int, index: int, kind: String="military") -> void:
	var profile: Dictionary=ItemsData.CONTAINERS[kind]
	var root := Node3D.new()
	root.position = pos + Vector3(0,0.65,0)
	root.set_meta("kind",kind)
	root.set_meta("label",str(profile.name)+" / %02d" % (index+1))
	root.set_meta("items",ItemsData.roll_container(kind,tier,loot_rng,raid_mode))
	root.set_meta("revealed",0)
	root.set_meta("search_elapsed",0.0)
	root.set_meta("searched",false)
	root.set_meta("tier",tier)
	add_child(root)
	var shell:=Arsenal.material(Color(profile.color),0.4)
	var extent:=Vector3(0.95,0.65,0.65)
	if kind in ["safe","filing","computer"]: extent=Vector3(0.75,1.2,0.65)
	if kind=="suitcase": extent=Vector3(0.9,0.62,0.35)
	if kind=="toolbox": extent=Vector3(0.8,0.42,0.45)
	Arsenal.box(root,extent,Vector3.ZERO,shell)
	Arsenal.box(root,Vector3(extent.x+0.025,0.06,extent.z+0.025),Vector3(0,extent.y/2,0),mats.dark)
	if kind=="medical":
		Arsenal.box(root,Vector3(0.11,0.36,0.03),Vector3(0,0,extent.z/2+0.02),mats.red)
		Arsenal.box(root,Vector3(0.36,0.11,0.03),Vector3(0,0,extent.z/2+0.03),mats.red)
	elif kind=="safe":
		Arsenal.box(root,Vector3(0.62,0.98,0.025),Vector3(0,0,0.34),mats.dark)
		Arsenal.box(root,Vector3(0.25,0.045,0.06),Vector3(0.1,0,0.38),mats.ivory)
	elif kind=="filing" or kind=="computer":
		for y in [-0.37,0.0,0.37]:
			Arsenal.box(root,Vector3(0.63,0.025,0.03),Vector3(0,y,0.34),mats.dark)
			Arsenal.box(root,Vector3(0.19,0.035,0.05),Vector3(0,y+0.1,0.36),mats.ivory)
	else:
		for x in [-0.28,0.28]:
			Arsenal.box(root,Vector3(0.055,extent.y+0.03,extent.z+0.03),Vector3(x,0,0),mats.yellow if kind=="military" else mats.dark)
		Arsenal.box(root,Vector3(0.3,0.07,0.07),Vector3(0,extent.y/2+0.06,0),mats.dark)
	var indicator:=Arsenal.box(root,Vector3(0.12,0.035,0.025),Vector3(-0.2,0.19,extent.z/2+0.04),mats.glow)
	indicator.name="Indicator"
	var body:=StaticBody3D.new()
	body.collision_layer=1
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=extent
	collision.shape=shape
	body.add_child(collision)
	root.add_child(body)
	solids.append(Rect2(pos.x-1.0,pos.z-0.9,2,1.8))
	loot.append(root)

func build_navigation() -> void:
	navigation.region = Rect2i(-54,-49,109,99)
	navigation.cell_size = Vector2(2,2)
	navigation.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.update()
	for rect in solids:
		var start := Vector2i(floori(rect.position.x/2),floori(rect.position.y/2))
		var end := Vector2i(ceili(rect.end.x/2),ceili(rect.end.y/2))
		for x in range(start.x,end.x+1):
			for y in range(start.y,end.y+1):
				var id := Vector2i(x,y)
				if navigation.is_in_boundsv(id): navigation.set_point_solid(id)

func free_cell(pos: Vector3) -> Vector2i:
	var cell := Vector2i(clampi(roundi(pos.x/2),-54,54),clampi(roundi(pos.z/2),-49,49))
	if not navigation.is_point_solid(cell): return cell
	for radius in range(1,7):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var id := cell+Vector2i(x,y)
				if navigation.is_in_boundsv(id) and not navigation.is_point_solid(id): return id
	return cell

func path_between(from: Vector3, to: Vector3) -> PackedVector2Array:
	return navigation.get_point_path(free_cell(from),free_cell(to))

func zone_name(pos: Vector3) -> String:
	if pos.z > 51: return "南侧接驳区"
	if pos.x > 35: return "储罐控制区" if pos.z < 0 else "东岸码头"
	if pos.x < -52 and pos.z < -13: return "海关办公区"
	if pos.x < -30: return "集装箱堆场"
	return "中央货运仓库"
