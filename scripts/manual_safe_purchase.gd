extends RefCounted
## The game only receives a public key. The merchant signs codes after checking payment.

const CONFIG_PATH := "res://data/manual_safe_purchase.json"
const Boxes = preload("res://scripts/safe_boxes.gd")
var config: Dictionary = {}
var config_path := CONFIG_PATH
var qr_texture: Texture2D
var verification_key := CryptoKey.new()
var key_ready := false

func _init(path: String=CONFIG_PATH) -> void:
	config_path=path
	reload_config()

func reload_config() -> void:
	config={}
	qr_texture=null
	key_ready=false
	verification_key=CryptoKey.new()
	if not FileAccess.file_exists(config_path): return
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary: return
	config=parsed
	var key_text:=str(config.get("public_key",""))
	if not key_text.is_empty(): key_ready=verification_key.load_from_string(key_text,true)==OK
	var path:=str(config.get("qr_image",""))
	if path.begins_with("res://assets/payments/") and ResourceLoader.exists(path):
		qr_texture=load(path) as Texture2D

func can_receive_payment() -> bool:
	return key_ready and qr_texture!=null

static func _decode(segment: String) -> PackedByteArray:
	if segment.is_empty() or segment.length()%4==1: return PackedByteArray()
	for c in segment:
		if not c in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_": return PackedByteArray()
	var padded:=segment.replace("-","+").replace("_","/")
	while padded.length()%4!=0: padded+="="
	return Marshalls.base64_to_raw(padded)

func verify(code: String, buyer: String) -> Dictionary:
	if not key_ready: return {"ok":false,"message":"激活服务尚未配置，请联系收款人。"}
	var clean:=code.replace("\r","").replace("\n","").replace(" ","").replace("\t","")
	if clean.length()>4096: return {"ok":false,"message":"激活码格式有误，请重新复制完整内容。"}
	var parts:=clean.split(".")
	if parts.size()!=3 or parts[0]!="GL1": return {"ok":false,"message":"激活码格式有误，请重新复制完整内容。"}
	var payload:=_decode(parts[1])
	var signature:=_decode(parts[2])
	if payload.is_empty() or signature.is_empty(): return {"ok":false,"message":"激活码不完整，请重新复制。"}
	var digest:=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(payload)
	if not Crypto.new().verify(HashingContext.HASH_SHA256,digest.finish(),signature,verification_key):
		return {"ok":false,"message":"激活码校验失败，请联系收款人重新核对。"}
	var data=JSON.parse_string(payload.get_string_from_utf8())
	if not data is Dictionary: return {"ok":false,"message":"激活码内容无效。"}
	if data.get("v")!=1 or data.get("product")!=Boxes.PRODUCT_ID or data.get("amount_fen")!=Boxes.PRICE_FEN:
		return {"ok":false,"message":"此激活码不适用于 2 × 4 永久保险箱。"}
	if data.get("buyer")!=buyer: return {"ok":false,"message":"激活码属于其他购买编号，请把本页编号发给收款人。"}
	var transaction:=str(data.get("transaction",""))
	if transaction.length()!=32 or not transaction.is_valid_hex_number(): return {"ok":false,"message":"激活码交易信息无效。"}
	return {"ok":true,"product":str(data.product),"transaction":"manual:"+transaction}
