#!/usr/bin/env python3
"""Seal preview signing values for GitHub Actions secret creation."""

import base64
import json
import os
import sys
from typing import NoReturn

from nacl.public import PublicKey, SealedBox

_SECRET_ENV = {
    "YCODE_RELEASE_JKS_BASE64": "YCODE_RELEASE_JKS_BASE64",
    "YCODE_RELEASE_STORE_PASSWORD": "YCODE_RELEASE_STORE_PASSWORD",
    "YCODE_RELEASE_KEY_ALIAS": "YCODE_RELEASE_KEY_ALIAS",
    "YCODE_RELEASE_KEY_PASSWORD": "YCODE_RELEASE_KEY_PASSWORD",
}


def fail(message: str) -> NoReturn:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def required(name: str) -> str:
    value = os.environ.get(name, "")
    if not value:
        fail(f"缺少环境变量 {name}")
    return value


def main() -> None:
    key_id = required("YCODE_SECRETS_KEY_ID")
    encoded_key = required("YCODE_SECRETS_PUBLIC_KEY")
    try:
        public_key = PublicKey(base64.b64decode(encoded_key, validate=True))
    except (ValueError, TypeError) as error:
        fail(f"YCODE_SECRETS_PUBLIC_KEY 无效：{error}")

    box = SealedBox(public_key)
    sealed = {}
    for secret_name, environment_name in _SECRET_ENV.items():
        encrypted = box.encrypt(required(environment_name).encode("utf-8"))
        sealed[secret_name] = {
            "key_id": key_id,
            "encrypted_value": base64.b64encode(encrypted).decode("ascii"),
        }
    json.dump(sealed, sys.stdout, separators=(",", ":"), sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
