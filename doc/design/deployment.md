# 运行与发布 | BY Weather Backend v1.1

> 文档版本：1.0  
> 相关文件：`pyproject.toml`、`uv.lock`、`environment.yml`、`Makefile`、`launcher.py`、`config.py`、`TEST_BYW.spec`

## 包管理理念

**远端 app 机器使用 uv，按 `uv.lock` 恢复 Python 3.14 虚拟环境；本地 Windows 可用 Conda 环境 `byw_py314` 模拟远端运行环境。**

远端 Linux app 机器的标准入口是 [pyproject.toml](../../pyproject.toml) 和 [uv.lock](../../uv.lock)。部署脚本会在发布目录下创建 `.venv`，执行：

```bash
uv venv .venv --python 3.14
uv sync --frozen --no-install-project --python 3.14
```

这里使用 `--no-install-project`，因为当前项目以源码目录方式运行 `app.py` / `launcher.py`，不需要把项目自身安装成 wheel，同时也避免触碰当前 `pyproject.toml` 的 build backend。

本地调试环境可继续使用 [environment.yml](../../environment.yml)，环境名为 `byw_py314`，只作为本机模拟和验证入口，不作为远端 app 机器部署入口。

当前运行依赖覆盖：

- Web 服务运行：`fastapi`、`uvicorn`、`requests`。
- 数据处理与本地云雷达：`numpy`、`scipy`、`pandas`、`xarray`。
- 试验脚本：`matplotlib`。

`pyinstaller`、`paramiko` 等打包或远程维护工具不作为远端 app 运行主依赖；如需在本机打包或执行远程维护脚本，应按需安装到 `byw_py314` 或单独维护打包环境。

本地首次创建模拟环境：

```bash
conda env create -f environment.yml
conda activate byw_py314
```

本地已有环境更新：

```bash
conda env update -n byw_py314 -f environment.yml --prune
conda activate byw_py314
```

从当前本地环境回写依赖清单时，优先人工维护 `environment.yml` 中的顶层依赖；如需完整锁定本地模拟环境，可另行导出完整快照：

```bash
conda env export -n byw_py314 > environment.lock.yml
```

`environment.lock.yml` 适合本地环境留档，不建议替代 `environment.yml` 作为日常维护入口。远端 app 机器以 `uv.lock` 为准。

## 开发运行

本地推荐使用启动器：

```bash
conda activate byw_py314
python launcher.py
```

本地直接运行 FastAPI：

```bash
conda activate byw_py314
python -m uvicorn app:app --host 127.0.0.1 --port 8010
```

默认地址：

- 页面：`http://127.0.0.1:8010`
- OpenAPI：`http://127.0.0.1:8010/docs`

## 启动器行为

`launcher.py` 做了比 `app.py` 更多的运行时准备：

1. 判断 `base_dir`。
2. 切换当前工作目录到 `base_dir`。
3. 设置 `BY_WEATHER_BASE_DIR`。
4. 把 `base_dir` 放入 `sys.path`。
5. 创建 `logs/`。
6. 将 stdout/stderr 同步写入 `logs/by_weather_YYYYMMDD.log`。
7. 加载运行目录下的 `config.py`。
8. 启动 Uvicorn。
9. 根据配置自动打开浏览器。

因此本地单机发布态应优先启动 `launcher.py` 或其打包 exe。远端 app 机器以 systemd user service 启动 `uvicorn app:app`。

## 配置

运行配置位于 `config.py`。发布目录中的 `config.py` 可以覆盖打包内默认配置。

重点配置：

```python
HOST = "127.0.0.1"
PORT = 8010
AUTO_OPEN_BROWSER = True

ALLOW_SIMULATED_FALLBACK = False
POLL_INTERVAL_SEC = 0.5
ALIGN_DELAY_SEC = 2.0
MWR_HOLD_SEC = 15
ICFP_LOOKBACK_SEC = 300
MAX_HISTORY_SECONDS = 3600
```

业务文件路径：

```python
TRACK_FILE = Path(...)
SCDP_FILE = Path(...)
ICFP_FILE = Path(...)
MWR_FILE = Path(...)
```

### 账号与密码

远端 app 机器不建议把账号明文写入 `config.py`。推荐在正式部署目录创建外部账号文件：

```bash
cd /opt/yujie/python_project
cp auth_users.example.json auth_users.json
python scripts/hash_password.py
```

将生成的哈希写入 `auth_users.json` 的 `password_hash` 字段：

```json
[
  {
    "username": "admin",
    "password_hash": "pbkdf2_sha256$...",
    "display_name": "full",
    "role": "full"
  },
  {
    "username": "lite",
    "password_hash": "pbkdf2_sha256$...",
    "display_name": "lite",
    "role": "lite"
  }
]
```

然后在 `.env` 中确认：

```env
BACKEND_AUTH_USERS_FILE=/opt/yujie/python_project/auth_users.json
```

`auth_users.json` 已加入 `.gitignore`，部署脚本更新时也会保留 `.env`，避免现场账号配置被源码包覆盖。

## 模拟数据

运行模拟器：

```bash
python simulate_realtime.py
```

模拟器会向 `simulated_data/` 中的实时文件追加数据。开发联调时可以把 `ALLOW_SIMULATED_FALLBACK` 改为 `True`，让主业务文件缺失时自动读取模拟文件。

业务验收或现场运行建议保持：

```python
ALLOW_SIMULATED_FALLBACK = False
```

## 日志

通过 `launcher.py` 启动时，日志写入：

```text
logs/by_weather_YYYYMMDD.log
```

日志包含：

- 启动目录。
- 加载的配置文件。
- 服务地址。
- 后台读取/对齐异常。
- 文件缺失警告。

## 静态资源

运行目录应包含：

```text
frontend/
  index.html
  styles.css
  app.js

reference/
  important_points.json
  watervapor_saturated_zone.py

map_tiles/
  {z}/{x}/{y}.png
```

`map_tiles/` 不存在时，系统仍可运行，但 `/api/map-config` 会返回 `has_local_tiles = false`。

## 远端 app 机器部署

远端 app 机器是 Linux，已安装 `uv`。部署流程是：本机生成源码包，上传到 app，解压到指定目录，然后用 `Makefile` 或 `scripts/deploy.sh` 恢复环境并安装 systemd user service。

本机生成发布包：

```bash
python scripts/package_release.py 20260617
```

上传到 app：

```bash
scp dist/backend-v1-20260617.tar.gz app:/tmp/
```

在 app 机器解压到指定目录：

```bash
sudo mkdir -p /opt/app/backend_v1.1
sudo tar -xzf /tmp/backend-v1-20260617.tar.gz -C /opt/app/backend_v1.1 --strip-components=1
cd /opt/app/backend_v1.1
```

安装依赖和服务：

```bash
sudo bash ./scripts/deploy.sh app /opt/app/backend_v1.1
```

部署脚本会：

1. 保留既有 `.env`，不存在时从 `.env.example` 生成。
2. 使用 `uv venv .venv --python 3.14` 创建虚拟环境。
3. 使用 `uv sync --frozen --no-install-project --python 3.14` 按锁文件恢复依赖。
4. 安装并 enable `backend-v1.service` 用户服务，但不会自动 start。

首次部署后先检查并修改 `.env`：

```bash
sudo -u app vi /opt/app/backend_v1.1/.env
```

启动、查看状态和日志：

```bash
make start TARGET_USER=app
make status TARGET_USER=app
make logs TARGET_USER=app
```

如果需要让用户服务在 app 用户未登录时仍可运行：

```bash
make linger TARGET_USER=app
```

部署包内保留 `environment.yml`，但它只用于本地 Conda 模拟环境；远端 app 机器不要用 Conda 还原运行环境。

### 已有目录更新

如果远端已经部署在 `/opt/yujie/python_project`，不要直接在运行目录里半解压半更新。推荐先解压到临时目录，再由 `deploy.sh` 用 `rsync --delete` 同步到正式目录。部署脚本会排除 `.env`、`.venv`、`logs`，因此会保留现场配置、虚拟环境目录和日志目录。

```bash
rm -rf /tmp/backend-v1-update
mkdir -p /tmp/backend-v1-update
tar -xzf /tmp/backend-v1-20260617.tar.gz -C /tmp/backend-v1-update --strip-components=1
cd /tmp/backend-v1-update
sudo bash ./scripts/deploy.sh yujie /opt/yujie/python_project
```

远端端口由正式目录中的 `.env` 控制。如果远端本来已经是 `UVICORN_PORT=8010`，更新时不需要再修改端口；部署脚本会保留既有 `.env`。

```bash
sudo -u yujie env XDG_RUNTIME_DIR=/run/user/$(id -u yujie) systemctl --user restart backend-v1
sudo -u yujie env XDG_RUNTIME_DIR=/run/user/$(id -u yujie) systemctl --user status backend-v1
```

## PyInstaller 打包

当前 spec 文件为：

```text
TEST_BYW.spec
```

构建前先进入 Conda 环境：

```bash
conda activate byw_py314
pyinstaller TEST_BYW.spec
```

入口：

```python
Analysis(["launcher.py"], ...)
```

构建后产物位于：

```text
dist/TEST_BYW/
```

发布时建议确认目录中至少包含：

```text
TEST_BYW.exe
config.py
environment.yml
frontend/
reference/
simulated_data/
map_tiles/
logs/
```

如需把资源自动纳入 PyInstaller，可后续补充 `datas` 配置；当前已有 `dist/TEST_BYW/` 目录显示资源是以发布目录方式携带。

## 冒烟验证

```bash
python smoke_test.py
```

运行后检查：

1. `/api/status` 是否能看到文件状态。
2. `/api/latest` 是否生成对齐帧。
3. WebSocket 状态是否连接。
4. 地图是否加载底图或离线瓦片。
5. SCDP/ICFP/MWR 图表是否随数据刷新。

## 常见问题

### 页面能打开但没有数据

检查：

- `config.py` 中业务文件路径是否存在。
- `ALLOW_SIMULATED_FALLBACK` 是否符合预期。
- `/api/status.file_states` 中 `path_exists`、`header_done`、`active_source`。
- 日志中是否有 header 不匹配或文件缺失。

### MWR 一直 partial

MWR 同一时间需要 `type` 为 `11`、`12`、`13`、`14` 的四组廓线。缺少任一组会生成 partial。

### Himawari 图层不可用

检查外网连接、日本气象厅接口可达性，以及 `/api/himawari/latest` 返回中的 `error` 字段。

### 打包后找不到前端

确认 exe 所在目录下有 `frontend/index.html`，且通过 `launcher.py` 启动时 `BY_WEATHER_BASE_DIR` 指向该目录。
