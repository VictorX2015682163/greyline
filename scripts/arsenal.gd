class_name Arsenal
extends RefCounted

const WeaponModsData = preload("res://scripts/weapon_mods.gd")

static var weapons: Array = []

static func all() -> Array:
	if weapons.is_empty():
		weapons = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
	return weapons

static func get_weapon(index: int) -> Dictionary:
	if index<0:
		return {"id":"unarmed","name":"未携带武器","type":"空装","caliber":"—","damage":0,"rpm":1,"magazine":0,"reserve":0,"reload":1.0,"range":0,"spread":0.0,"recoil":0.0,"automatic":false,"pellets":0,"weight":0.0,"price":0,"value":0}
	return all()[clampi(index, 0, 7)]

static func material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = 0.67
	return mat

static func box(root: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = pos
	root.add_child(mesh)
	return mesh

static func cylinder(root: Node3D, radius: float, length: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = length
	shape.radial_segments = 12
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation.x = PI / 2.0
	root.add_child(mesh)
	return mesh

# Models point down -Z, shared by the armory and the first person camera.
static func build_model(index: int, build: Dictionary={}) -> Node3D:
	var data := get_weapon(index)
	var root := Node3D.new()
	if index<0: return root
	var steel := material(Color("283038"), 0.7)
	var dark := material(Color("161e24"), 0.35)
	var accent := material(Color(data.color), 0.3)
	var rubber := material(Color("12181b"))
	var length: float = [0.82, 0.88, 0.58, 0.55, 0.99, 1.02, 1.04, 1.16][index]
	box(root, Vector3(0.085, 0.105, 0.34), Vector3(0, 0, -0.04), steel)
	box(root, Vector3(0.069, 0.07, length * 0.31), Vector3(0, 0.006, -0.3), accent)
	cylinder(root, 0.017, length * 0.34, Vector3(0, 0.014, -length * 0.55), steel)
	cylinder(root, 0.025, 0.065, Vector3(0, 0.014, -length * 0.72), dark)
	var stock := box(root, Vector3(0.075, 0.13, 0.22), Vector3(0, -0.025, 0.23), accent)
	stock.rotation.x = -0.08
	box(root, Vector3(0.081, 0.14, 0.025), Vector3(0, -0.025, 0.35), rubber)
	var grip := box(root, Vector3(0.06, 0.15, 0.065), Vector3(0, -0.11, 0.06), dark)
	grip.rotation.x = -0.3
	if index==7:
		grip.scale=Vector3(1,0.55,2.2)
		grip.position=Vector3(0,-0.055,0.09)
		grip.material_override=accent
	if index in [0,2,3,6]:
		stock.scale=Vector3(0.8,0.75,0.75)
		cylinder(root,0.022,0.19,Vector3(0,0.012,0.17),steel)
	if index==2:
		cylinder(root,0.046,0.27,Vector3(0,0.006,-0.25),dark)
		cylinder(root,0.024,0.13,Vector3(-0.035,0.05,-0.23),steel)
	# Receiver details and contrasting hardware provide scale in the armory view.
	box(root,Vector3(0.003,0.036,0.09),Vector3(0.044,0.015,-0.043),rubber)
	box(root,Vector3(0.016,0.012,0.065),Vector3(0.049,-0.005,-0.042),steel)
	for z in [-0.13,0.06]:
		var pin:=cylinder(root,0.007,0.091,Vector3(0,-0.018,z),accent)
		pin.rotation=Vector3(0,0,PI/2)
	box(root,Vector3(0.093,0.012,0.025),Vector3(0,0.049,0.1),steel)
	box(root, Vector3(0.042, 0.012, 0.085), Vector3(0, -0.09, -0.028), steel)
	box(root, Vector3(0.012, 0.07, 0.014), Vector3(0, -0.06, -0.068), steel)
	box(root, Vector3(0.044, 0.018, 0.31), Vector3(0, 0.065, -0.05), dark)
	for i in range(13):
		box(root, Vector3(0.052, 0.007, 0.009), Vector3(0, 0.078, -0.19 + i * 0.023), steel)
	for i in range(7):
		box(root, Vector3(0.074, 0.008, 0.013), Vector3(0, -0.037, -0.2 - i * 0.027), dark)
	if index == 4:
		cylinder(root, 0.023, 0.38, Vector3(0, -0.038, -0.33), steel)
		box(root, Vector3(0.092, 0.08, 0.17), Vector3(0, -0.018, -0.3), accent)
	elif index == 5:
		box(root, Vector3(0.19, 0.17, 0.19), Vector3(0.018, -0.13, -0.06), accent)
		for side in [-1.0, 1.0]:
			var leg := box(root, Vector3(0.018, 0.22, 0.02), Vector3(side * 0.065, -0.13, -0.39), steel)
			leg.rotation.z = side * 0.24
	elif index != 7:
		var magazine := box(root, Vector3(0.062, 0.2 if index != 3 else 0.24, 0.085), Vector3(0, -0.145, -0.10 if index != 3 else 0.025), accent if index == 1 else dark)
		magazine.rotation.x = 0.15 if index == 1 else -0.08
	if index >= 6 and not build.has("optic"):
		box(root, Vector3(0.055, 0.04, 0.17), Vector3(0, 0.095, -0.01), dark)
		cylinder(root, 0.039, 0.29, Vector3(0, 0.14, -0.06), dark)
		cylinder(root, 0.045, 0.055, Vector3(0, 0.14, -0.2), steel)
		var glass := material(Color("428e95"), 0.65)
		cylinder(root, 0.037, 0.004, Vector3(0, 0.14, -0.23), glass)
		cylinder(root, 0.034, 0.004, Vector3(0, 0.14, 0.088), glass)
	else:
		box(root, Vector3(0.047, 0.055, 0.055), Vector3(0, 0.098, 0.07), dark)
		box(root, Vector3(0.014, 0.05, 0.018), Vector3(0, 0.06, -length * 0.58), steel)
	if index == 3:
		box(root, Vector3(0.105, 0.18, 0.12), Vector3(0, -0.045, -0.04), accent)
	if index == 1 or index == 4:
		for i in range(5):
			box(root, Vector3(0.077, 0.004, 0.008), Vector3(0, 0.044, -0.2 - i * 0.028), dark)
	add_mod_models(root,index,WeaponModsData.sanitize(index,build))
	return root

static func add_mod_models(root: Node3D, index: int, build: Dictionary) -> void:
	var dark:=material(Color("182428"),0.5)
	var metal:=material(Color("8c9b95"),0.65)
	var glass:=material(Color("51c6b0"),0.7)
	var length: float=[0.82,0.88,0.58,0.55,0.99,1.02,1.04,1.16][index]
	if build.has("optic"):
		box(root,Vector3(0.065,0.035,0.14),Vector3(0,0.095,-0.04),metal)
		if build.optic=="red_dot":
			box(root,Vector3(0.075,0.075,0.045),Vector3(0,0.15,-0.06),dark)
			box(root,Vector3(0.05,0.05,0.048),Vector3(0,0.15,-0.06),glass)
		else:
			cylinder(root,0.043,0.32 if build.optic=="scope_8x" else 0.24,Vector3(0,0.15,-0.05),dark)
			cylinder(root,0.047,0.008,Vector3(0,0.15,-0.215 if build.optic=="scope_8x" else -0.175),glass)
	if build.has("muzzle"):
		var suppressed: bool=build.muzzle=="suppressor"
		cylinder(root,0.038 if suppressed else 0.029,0.22 if suppressed else 0.08,Vector3(0,0.014,-length*0.75-0.08),dark if suppressed else metal)
	if build.has("grip"):
		var grip:=box(root,Vector3(0.04,0.13,0.045),Vector3(0,-0.105,-0.3),dark)
		grip.rotation.x=0.45 if build.grip=="grip_angled" else 0.0
	if build.get("magazine","")=="mag_extended":
		box(root,Vector3(0.075,0.11,0.09),Vector3(0,-0.28,-0.09),metal)
	if build.has("stock"):
		box(root,Vector3(0.09,0.15,0.08 if build.stock=="stock_stable" else 0.025),Vector3(0,-0.02,0.34),metal)
	if build.has("barrel"):
		cylinder(root,0.023,0.24 if build.barrel=="barrel_long" else 0.06,Vector3(0,0.015,-length*0.64),metal)
