extends RefCounted
## Entitlements are separate from raid cargo and the in-game currency balance.
## A payment adapter must verify a receipt before calling fulfill_purchase().

const DEFAULT_ID := "safe_1x2"
const PAID_ID := "safe_2x4"
const PRODUCT_ID := "greyline.safe_2x4.permanent"
const PRICE_FEN := 1000
const CATALOGUE := [
	{"id":"safe_1x2", "name":"基础保险箱", "columns":1, "rows":2, "access":"starter"},
	{"id":"safe_2x2", "name":"进阶保险箱", "columns":2, "rows":2, "access":"season", "goals":{"extracts":3,"value":30000}},
	{"id":"safe_2x4", "name":"永久保险箱", "columns":2, "rows":4, "access":"purchase"},
	{"id":"safe_3x3", "name":"精英保险箱", "columns":3, "rows":3, "access":"season", "goals":{"extracts":10,"value":150000,"kills":20}},
]

var season := ""
var progress: Dictionary = {"extracts":0,"value":0,"kills":0}
var seasonal: Dictionary = {}
var permanent: Dictionary = {}
var transactions: Array = []
var equipped := DEFAULT_ID
var purchase_id := new_purchase_id()

static func new_purchase_id() -> String:
	return "GL-"+Crypto.new().generate_random_bytes(10).hex_encode().to_upper()

static func valid_purchase_id(id: String) -> bool:
	return id.length()==23 and id.begins_with("GL-") and id.substr(3).is_valid_hex_number() and id==id.to_upper()

static func definition(id: String) -> Dictionary:
	for box in CATALOGUE:
		if box.id==id: return box
	return {}

static func current_season() -> String:
	# Seasons follow calendar quarters in China Standard Time.
	var date:=Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system())+8*3600)
	return "%d-S%d" % [int(date.year),ceili(int(date.month)/3.0)]

static func season_deadline(id: String) -> String:
	var quarter:=clampi(int(id.get_slice("S",1)),1,4)
	var month:=quarter*3
	return "%s/%02d/%02d 23:59（北京时间）" % [id.get_slice("-",0),month,30 if month in [6,9] else 31]

func refresh_season(id: String="") -> bool:
	var active:=current_season() if id.is_empty() else id
	var changed:=season!=active
	if changed:
		season=active
		progress={"extracts":0,"value":0,"kills":0}
		seasonal.clear()
	if not available(equipped): equipped=DEFAULT_ID
	return changed

func available(id: String) -> bool:
	var box:=definition(id)
	if box.is_empty(): return false
	match str(box.access):
		"starter": return true
		"season": return bool(seasonal.get(id,false))
		"purchase": return bool(permanent.get(id,false))
	return false

func task_complete(id: String) -> bool:
	var box:=definition(id)
	if box.get("access","")!="season": return false
	for key in box.goals:
		if int(progress.get(key,0))<int(box.goals[key]): return false
	return true

func claim(id: String) -> bool:
	refresh_season()
	if available(id) or not task_complete(id): return false
	seasonal[id]=true
	equipped=id
	return true

func equip(id: String) -> bool:
	refresh_season()
	if not available(id): return false
	equipped=id
	return true

func record_raid(success: bool, cargo: Array, kills: int, raid_season: String) -> void:
	refresh_season()
	# Cross-season raids retain cargo without advancing the new season's tasks.
	if raid_season!=season: return
	progress.kills=int(progress.kills)+maxi(0,kills)
	if not success: return
	progress.extracts=int(progress.extracts)+1
	for item in cargo: progress.value=int(progress.value)+maxi(0,int(item.get("value",0)))

func fulfill_purchase(product: String, transaction: String) -> bool:
	# Trusted fulfillment boundary: never expose this as a UI action or client RPC.
	if product!=PRODUCT_ID or transaction.strip_edges().is_empty() or transaction in transactions: return false
	transactions.append(transaction)
	permanent[PAID_ID]=true
	return true

func serialize() -> Dictionary:
	return {"season":season,"progress":progress.duplicate(true),"seasonal":seasonal.duplicate(true),"permanent":permanent.duplicate(true),"transactions":transactions.duplicate(),"equipped":equipped,"purchase_id":purchase_id}

func restore(data: Dictionary) -> void:
	var saved_id:=str(data.get("purchase_id",""))
	if valid_purchase_id(saved_id): purchase_id=saved_id
	season=str(data.get("season",""))
	progress={"extracts":0,"value":0,"kills":0}
	if data.get("progress") is Dictionary:
		for key in progress: progress[key]=maxi(0,int(data.progress.get(key,0)))
	seasonal.clear()
	if data.get("seasonal") is Dictionary:
		for id in ["safe_2x2","safe_3x3"]: seasonal[id]=data.seasonal.get(id,false)==true
	permanent={PAID_ID:false}
	if data.get("permanent") is Dictionary: permanent[PAID_ID]=data.permanent.get(PAID_ID,false)==true
	transactions=data.get("transactions",[]).duplicate() if data.get("transactions",[]) is Array else []
	equipped=str(data.get("equipped",DEFAULT_ID))
	refresh_season()
