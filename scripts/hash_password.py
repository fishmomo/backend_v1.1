#!/usr/bin/env python3
"""Generate a password hash for BACKEND_AUTH_USERS_JSON or auth_users.json."""

from __future__ import annotations

import getpass
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from auth import hash_password  # noqa: E402


def main() -> None:
    password = getpass.getpass('Password: ')
    confirm = getpass.getpass('Confirm: ')
    if password != confirm:
        raise SystemExit('passwords do not match')
    print(hash_password(password))


if __name__ == '__main__':
    main()
