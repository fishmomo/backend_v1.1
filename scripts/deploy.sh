#!/usr/bin/env bash
# Remote deployment script for the Linux app host.
#
# Run this after extracting backend-v1-<tag>.tar.gz on the target host.
#
# Usage:
#   sudo bash ./scripts/deploy.sh <user> [install-dir]
#
# Examples:
#   sudo bash ./scripts/deploy.sh app
#   sudo bash ./scripts/deploy.sh app /opt/app/backend_v1.1
#
# The script:
#   1. Installs source to INSTALL_DIR or /opt/<user>/backend_v1.1
#   2. Creates/updates .venv via uv and uv.lock
#   3. Sets up .env from .env.example, preserving existing .env
#   4. Installs/enables the systemd user service
#   5. Prints start/status/log commands
set -euo pipefail

REPO_NAME="${REPO_NAME:-backend_v1.1}"
SERVICE_NAME="${SERVICE_NAME:-backend-v1}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

if [ $# -lt 1 ]; then
  echo "Usage: sudo $0 <user> [install-dir]"
  echo "Example: sudo $0 app /opt/app/backend_v1.1"
  exit 1
fi

TARGET_USER="$1"
INSTALL_DIR="${2:-${INSTALL_DIR:-/opt/${TARGET_USER}/${REPO_NAME}}}"
VENV_DIR="${INSTALL_DIR}/.venv"
USER_SERVICE_DIR="/home/${TARGET_USER}/.config/systemd/user"
SERVICE_FILE="${USER_SERVICE_DIR}/${SERVICE_NAME}.service"
CURRENT_USER="$(id -un)"
CURRENT_UID="$(id -u)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Deploying backend-v1"
echo "    User:        ${TARGET_USER}"
echo "    Source:      ${SOURCE_DIR}"
echo "    Install to:  ${INSTALL_DIR}"
echo "    Python:      ${PYTHON_VERSION}"
echo "    Env tool:    uv"

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "Target user does not exist: ${TARGET_USER}"
  exit 1
fi

run_as_target() {
  local command="$1"
  if [ "${CURRENT_USER}" = "${TARGET_USER}" ]; then
    bash -lc "${command}"
  elif [ "${CURRENT_UID}" = "0" ]; then
    su - "${TARGET_USER}" -c "${command}"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "${TARGET_USER}" bash -lc "${command}"
  else
    echo "Current user is ${CURRENT_USER}, target user is ${TARGET_USER}, and neither root nor sudo is available."
    echo "Log in as ${TARGET_USER} or run this script as root."
    exit 1
  fi
}

echo "==> [1/5] Installing source files..."
if [ "${CURRENT_UID}" = "0" ]; then
  install -d -o "${TARGET_USER}" -g "${TARGET_USER}" "${INSTALL_DIR}"
else
  mkdir -p "${INSTALL_DIR}"
fi
if [ -d "${INSTALL_DIR}/src" ]; then
  find "${INSTALL_DIR}/src" -type d -name '__pycache__' -prune -exec rm -rf {} +
  find "${INSTALL_DIR}/src" -depth -type d -empty -delete
fi
SOURCE_REAL="$(cd "${SOURCE_DIR}" && pwd -P)"
INSTALL_REAL="$(cd "${INSTALL_DIR}" && pwd -P)"

if [ "${SOURCE_REAL}" != "${INSTALL_REAL}" ]; then
  rsync -a --delete "${SOURCE_DIR}/" "${INSTALL_DIR}/" \
    --exclude='.venv' \
    --exclude='.env' \
    --exclude='auth_users.json' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.git' \
    --exclude='build' \
    --exclude='dist' \
    --exclude='logs'
else
  echo "    Source is already the install directory; skipping copy."
fi
if [ "${CURRENT_UID}" = "0" ]; then
  chown -R "${TARGET_USER}:${TARGET_USER}" "${INSTALL_DIR}"
fi

echo "==> [2/5] Setting up .env..."
if [ ! -f "${INSTALL_DIR}/.env" ]; then
  cp "${INSTALL_DIR}/.env.example" "${INSTALL_DIR}/.env"
  if [ "${CURRENT_UID}" = "0" ]; then
    chown "${TARGET_USER}:${TARGET_USER}" "${INSTALL_DIR}/.env"
  fi
  echo "    Created ${INSTALL_DIR}/.env from .env.example"
else
  echo "    .env already exists, keeping it"
fi

echo "==> [3/5] Restoring Python environment with uv..."
run_as_target "
  set -e
  cd '${INSTALL_DIR}'
  command -v uv >/dev/null
  if [ ! -x .venv/bin/python ]; then
    uv venv .venv --python '${PYTHON_VERSION}'
  fi
  uv sync --frozen --no-install-project --python '${PYTHON_VERSION}'
  .venv/bin/python -B -c 'import app; print(app.app.title)'
"

echo "==> [4/5] Installing systemd user service..."
if [ "${CURRENT_UID}" = "0" ]; then
  install -d -o "${TARGET_USER}" -g "${TARGET_USER}" "${USER_SERVICE_DIR}"
else
  mkdir -p "${USER_SERVICE_DIR}"
fi
sed \
  -e "s|__INSTALL_DIR__|${INSTALL_DIR}|g" \
  -e "s|__VENV_DIR__|${VENV_DIR}|g" \
  "${INSTALL_DIR}/deploy/${SERVICE_NAME}.service" > "${SERVICE_FILE}"
if [ "${CURRENT_UID}" = "0" ]; then
  chown "${TARGET_USER}:${TARGET_USER}" "${SERVICE_FILE}"
fi

USER_UID="$(id -u "${TARGET_USER}")"
run_as_target "XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user daemon-reload"
run_as_target "XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user enable ${SERVICE_NAME}.service"

echo "==> [5/5] Done."
echo ""
echo "Service installed but not started."
echo ""
echo "Edit config before starting:"
echo "  sudo -u ${TARGET_USER} vi ${INSTALL_DIR}/.env"
echo ""
echo "Start:"
echo "  sudo -u ${TARGET_USER} env XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user start ${SERVICE_NAME}"
echo ""
echo "Status:"
echo "  sudo -u ${TARGET_USER} env XDG_RUNTIME_DIR=/run/user/${USER_UID} systemctl --user status ${SERVICE_NAME}"
echo ""
echo "Logs:"
echo "  sudo -u ${TARGET_USER} env XDG_RUNTIME_DIR=/run/user/${USER_UID} journalctl --user -u ${SERVICE_NAME} -f"
