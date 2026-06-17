SHELL := /bin/bash

TAG ?= $(shell date +%Y%m%d-%H%M)
TARGET_USER ?= app
INSTALL_DIR ?= /opt/$(TARGET_USER)/backend_v1.1
PYTHON_VERSION ?= 3.14
SERVICE_NAME ?= backend-v1

.PHONY: help package env check deploy linger start stop restart status logs

help:
	@echo "Targets:"
	@echo "  make package                 Build dist/backend-v1-<tag>.tar.gz"
	@echo "  make env                     Restore .venv with uv and uv.lock"
	@echo "  make check                   Verify imports in the local .venv"
	@echo "  make deploy TARGET_USER=app  Install to $(INSTALL_DIR) and create user service"
	@echo "  make start|stop|restart|status|logs TARGET_USER=app"
	@echo ""
	@echo "Variables: TAG, TARGET_USER, INSTALL_DIR, PYTHON_VERSION, SERVICE_NAME"

package:
	python3 scripts/package_release.py $(TAG)

env:
	uv venv .venv --python $(PYTHON_VERSION)
	uv sync --frozen --no-install-project --python $(PYTHON_VERSION)

check:
	.venv/bin/python -B -m py_compile app.py launcher.py config.py auth.py models.py readers.py aligner.py store.py publisher.py local_radar.py mwr_saturation.py simulate_realtime.py
	.venv/bin/python -B -c "import app; print(app.app.title)"

deploy:
	sudo PYTHON_VERSION=$(PYTHON_VERSION) INSTALL_DIR=$(INSTALL_DIR) SERVICE_NAME=$(SERVICE_NAME) bash ./scripts/deploy.sh $(TARGET_USER)

linger:
	sudo loginctl enable-linger $(TARGET_USER)

start:
	sudo -u $(TARGET_USER) env XDG_RUNTIME_DIR=/run/user/$$(id -u $(TARGET_USER)) systemctl --user start $(SERVICE_NAME)

stop:
	sudo -u $(TARGET_USER) env XDG_RUNTIME_DIR=/run/user/$$(id -u $(TARGET_USER)) systemctl --user stop $(SERVICE_NAME)

restart:
	sudo -u $(TARGET_USER) env XDG_RUNTIME_DIR=/run/user/$$(id -u $(TARGET_USER)) systemctl --user restart $(SERVICE_NAME)

status:
	sudo -u $(TARGET_USER) env XDG_RUNTIME_DIR=/run/user/$$(id -u $(TARGET_USER)) systemctl --user status $(SERVICE_NAME)

logs:
	sudo -u $(TARGET_USER) env XDG_RUNTIME_DIR=/run/user/$$(id -u $(TARGET_USER)) journalctl --user -u $(SERVICE_NAME) -f
