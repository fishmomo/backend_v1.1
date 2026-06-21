import base64
import hashlib
import hmac
import json
import os
import secrets
import time
from typing import Optional

import config


COOKIE_NAME = 'by_weather_session'
DEFAULT_AUTH_USERS = [
    {
        'username': 'admin',
        'password_hash': 'pbkdf2_sha256$260000$33c4785ec8e60aa6c0f49bd68bd347b3$f6675600c506ed02f6d490a2b5777034d7333f4a29005a9b8e5c5087d400ff53',
        'display_name': '全量账号',
        'role': 'full',
    },
    {
        'username': 'lite',
        'password_hash': 'pbkdf2_sha256$260000$8ff35c6730f690db17fbcba15a07ee2a$97758d2ab869d864d0300b9c3b75cede6a51240ead8f3f1fe99e121eef43fe1a',
        'display_name': '精简账号',
        'role': 'lite',
    },
]
PBKDF2_ITERATIONS = 260_000


def is_auth_enabled() -> bool:
    return bool(getattr(config, 'AUTH_ENABLED', True))


def role_permissions(role: str) -> list:
    permissions = getattr(config, 'ROLE_PERMISSIONS', {})
    if not permissions:
        permissions = {
            'full': ['view_all'],
            'lite': ['view_map', 'view_replay', 'view_weather_overlays'],
        }
    return list(permissions.get(role, []))


def public_user(user: dict) -> dict:
    role = user.get('role', 'lite')
    return {
        'username': user.get('username'),
        'display_name': user.get('display_name') or user.get('username'),
        'role': role,
        'permissions': role_permissions(role),
    }


def system_user() -> dict:
    return {
        'username': 'system',
        'display_name': 'System',
        'role': 'full',
        'permissions': role_permissions('full'),
    }


def has_permission(user: Optional[dict], permission: str) -> bool:
    if not is_auth_enabled():
        return True
    if not user:
        return False
    return permission in set(user.get('permissions') or role_permissions(user.get('role', 'lite')))


def hash_password(password: str, *, iterations: int = PBKDF2_ITERATIONS) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        'sha256',
        str(password).encode('utf-8'),
        salt.encode('ascii'),
        iterations,
    ).hex()
    return f'pbkdf2_sha256${iterations}${salt}${digest}'


def _hash_password_sha256(password: str) -> str:
    return hashlib.sha256(password.encode('utf-8')).hexdigest()


def _password_matches(password: str, stored: str) -> bool:
    stored = str(stored or '')
    if stored.startswith('pbkdf2_sha256$'):
        try:
            _, iterations, salt, expected = stored.split('$', 3)
            digest = hashlib.pbkdf2_hmac(
                'sha256',
                password.encode('utf-8'),
                salt.encode('ascii'),
                int(iterations),
            ).hex()
        except Exception:
            return False
        return hmac.compare_digest(digest, expected)
    if stored.startswith('sha256:'):
        return hmac.compare_digest(_hash_password_sha256(password), stored.split(':', 1)[1])
    return hmac.compare_digest(password, stored)


def _configured_auth_users() -> list:
    users = getattr(config, 'AUTH_USERS', None)
    if users is not None:
        return list(users)
    return DEFAULT_AUTH_USERS


def authenticate(username: str, password: str) -> Optional[dict]:
    username = str(username or '').strip()
    password = str(password or '')
    for item in _configured_auth_users():
        if item.get('username') != username:
            continue
        if _password_matches(password, item.get('password') or item.get('password_hash')):
            role = item.get('role', 'lite')
            return {
                'username': username,
                'display_name': item.get('display_name') or username,
                'role': role,
                'permissions': role_permissions(role),
            }
    return None


def _sign(payload_b64: str) -> str:
    return hmac.new(
        str(getattr(config, 'AUTH_SECRET_KEY', 'change-this-local-session-secret')).encode('utf-8'),
        payload_b64.encode('utf-8'),
        hashlib.sha256,
    ).hexdigest()


def create_session_token(user: dict) -> str:
    payload = {
        'username': user.get('username'),
        'display_name': user.get('display_name'),
        'role': user.get('role', 'lite'),
        'exp': int(time.time()) + int(getattr(config, 'SESSION_TTL_SECONDS', 12 * 60 * 60)),
    }
    raw = json.dumps(payload, separators=(',', ':'), ensure_ascii=True).encode('utf-8')
    payload_b64 = base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=')
    return f'{payload_b64}.{_sign(payload_b64)}'


def verify_session_token(token: str) -> Optional[dict]:
    if not token or '.' not in token:
        return None
    payload_b64, signature = token.rsplit('.', 1)
    if not hmac.compare_digest(_sign(payload_b64), signature):
        return None
    padded = payload_b64 + '=' * (-len(payload_b64) % 4)
    try:
        payload = json.loads(base64.urlsafe_b64decode(padded.encode('ascii')).decode('utf-8'))
    except Exception:
        return None
    if int(payload.get('exp') or 0) < int(time.time()):
        return None
    role = payload.get('role', 'lite')
    return {
        'username': payload.get('username'),
        'display_name': payload.get('display_name') or payload.get('username'),
        'role': role,
        'permissions': role_permissions(role),
    }
