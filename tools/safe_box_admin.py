#!/usr/bin/env python3
"""Merchant-only setup and code issuance after manually confirming WeChat payment."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "data/manual_safe_purchase.json"
DEFAULT_MERCHANT = Path.home() / ".local/share/greyline-merchant"
PRODUCT = "greyline.safe_2x4.permanent"
PRICE_FEN = 1000


def openssl(*args, data=None):
    result = subprocess.run(["openssl", *map(str, args)], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise ValueError("OpenSSL 操作失败，请检查密钥文件和 OpenSSL 安装。")
    return result.stdout


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def read_config(path):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def setup(merchant_dir, config_path):
    merchant_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    key_path = merchant_dir / "signing_private.pem"
    if not key_path.exists():
        if read_config(config_path).get("public_key"):
            raise ValueError("购买页已有公钥，但这里找不到对应私钥；请恢复原私钥，不能直接替换。")
        handle, temporary = tempfile.mkstemp(prefix=".signing-", dir=merchant_dir)
        os.close(handle)
        try:
            openssl("genrsa", "-out", temporary, "2048")
            os.chmod(temporary, 0o600)
            os.replace(temporary, key_path)
        finally:
            Path(temporary).unlink(missing_ok=True)
    public_key = openssl("rsa", "-in", key_path, "-pubout").decode("ascii")
    config = read_config(config_path)
    if config.get("public_key") not in (None, "", public_key):
        raise ValueError("私钥与购买页的公钥不匹配；已停止，现有配置未更改。")
    config.update(public_key=public_key)
    config.setdefault("qr_image", "")
    config.setdefault("wechat_contact", "")
    write_json(config_path, config)
    return key_path


def encode(value):
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def issue(merchant_dir, config_path, buyer, receipt):
    if not re.fullmatch(r"GL-[0-9A-F]{20}", buyer):
        raise ValueError("购买编号格式错误，请复制买家购买页上完整的 GL- 编号。")
    receipt = receipt.strip()
    if not receipt or len(receipt) > 128:
        raise ValueError("需要提供真实到账交易单号，最长 128 字符。")
    key_path = merchant_dir / "signing_private.pem"
    if not key_path.exists():
        raise ValueError("还未初始化发码密钥，请先运行 setup。")
    public_key = openssl("rsa", "-in", key_path, "-pubout").decode("ascii")
    if read_config(config_path).get("public_key") != public_key:
        raise ValueError("发码密钥与游戏配置不匹配。")
    ledger_path = merchant_dir / "orders.jsonl"
    # Keep the receipt check and append in one lock, including simultaneous invocations.
    handle = os.open(ledger_path, os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(handle, "r+", encoding="utf-8") as ledger:
        if os.name == "posix":
            import fcntl
            fcntl.flock(ledger, fcntl.LOCK_EX)
        elif os.name == "nt":
            import msvcrt
            msvcrt.locking(ledger.fileno(), msvcrt.LK_LOCK, 1)
        receipt_hash = hashlib.sha256(receipt.encode("utf-8")).hexdigest()
        for line in ledger:
            entry = json.loads(line)
            if entry["receipt_hash"] == receipt_hash:
                if entry["buyer"] != buyer:
                    raise ValueError("此到账单号已为其他购买编号发码，不能重复使用。")
                return entry["code"]
        data = {"v": 1, "buyer": buyer, "product": PRODUCT, "amount_fen": PRICE_FEN,
                "transaction": uuid.uuid4().hex}
        payload = json.dumps(data, separators=(",", ":")).encode("ascii")
        signature = openssl("dgst", "-sha256", "-sign", key_path, data=payload)
        code = "GL1." + encode(payload) + "." + encode(signature)
        entry = {"buyer": buyer, "receipt_hash": receipt_hash, "code": code}
        ledger.seek(0, os.SEEK_END)
        ledger.write(json.dumps(entry) + "\n")
        ledger.flush()
        os.fsync(ledger.fileno())
        return code


def configure_qr(config_path, image, contact):
    config = read_config(config_path)
    if image is not None:
        source = image.expanduser().resolve()
        header = source.read_bytes()[:8]
        if header == b"\x89PNG\r\n\x1a\n":
            extension = ".png"
        elif header[:3] == b"\xff\xd8\xff":
            extension = ".jpg"
        else:
            raise ValueError("收款码需要 PNG 或 JPEG 图片。")
        target = ROOT / ("assets/payments/wechat_collection" + extension)
        target.parent.mkdir(parents=True, exist_ok=True)
        if source != target.resolve():
            shutil.copyfile(source, target)
        config["qr_image"] = "res://" + str(target.relative_to(ROOT))
    if contact is not None:
        if len(contact) > 40:
            raise ValueError("微信联系方式最长 40 字符。")
        config["wechat_contact"] = contact
    write_json(config_path, config)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--merchant-dir", type=Path, default=DEFAULT_MERCHANT)
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("setup", help="首次生成私钥，并把公钥配置到游戏")
    configure = sub.add_parser("configure", help="放入真实微信收款码，可选显示微信联系方式")
    configure.add_argument("--qr", type=Path)
    configure.add_argument("--wechat")
    grant = sub.add_parser("issue", help="核对微信实际到账后，按购买编号发码")
    grant.add_argument("--buyer", required=True)
    grant.add_argument("--receipt", required=True, help="实际到账交易单号，不是截图编号")
    args = parser.parse_args()
    try:
        if args.command == "setup":
            key_path = setup(args.merchant_dir, args.config)
            print("发码工具已就绪。私钥仅保存在：" + str(key_path))
        elif args.command == "configure":
            if args.qr is None and args.wechat is None:
                parser.error("configure 至少需要 --qr 或 --wechat")
            configure_qr(args.config, args.qr, args.wechat)
            print("收款页配置已保存，请重新打开购买页。")
        else:
            print(issue(args.merchant_dir, args.config, args.buyer.upper(), args.receipt))
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        parser.exit(1, "未完成：" + str(exc) + "\n")


if __name__ == "__main__":
    main()
