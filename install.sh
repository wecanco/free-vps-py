#!/usr/bin/env bash
# ------------------------------------------------------------------
#  Python-Xray-Argo one-key deployment (ASCII-only edition)
#  Tested on a Node.js Docker image with bash
# ------------------------------------------------------------------
set -euo pipefail

# --- helpers ------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "import uuid, sys; sys.stdout.write(str(uuid.uuid4()))"
    else
        hexdump -n 16 -e '4/4 "%08X"' /dev/urandom |
        awk '{print substr($0,1,8)"-"substr($0,9,4)"-"substr($0,13,4)"-"substr($0,17,4)"-"substr($0,21,12)}' |
        tr '[:upper:]' '[:lower:]'
    fi
}

# --- system deps --------------------------------------------------
install_system_deps() {
    log_info "Installing system packages (python3, pip3, git, unzip) ..."
    apt-get update -qq
    apt-get install -y python3 python3-pip git unzip
}

# --- python deps --------------------------------------------------
install_python_deps() {
    local req_file="$1"
    if [[ -f "$req_file" ]]; then
        log_info "Installing Python dependencies from $req_file ..."
        python3 -m pip install --upgrade pip -q
        python3 -m pip install -r "$req_file" -q
    else
        log_warn "requirements.txt not found – skipping pip install"
    fi
}

# --- clone repo ---------------------------------------------------
clone_repo() {
    local repo="https://github.com/eooce/python-xray-argo.git"
    local dir="python-xray-argo"

    if [[ -d "$dir" ]]; then
        log_warn "Directory $dir already exists – pulling latest changes"
        git -C "$dir" pull --ff-only
    else
        log_info "Cloning $repo ..."
        git clone "$repo" "$dir"
    fi
    echo "$dir"
}

# --- select mode --------------------------------------------------
select_mode() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Python-Xray-Argo quick deploy script ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}Project:${NC} https://github.com/eooce/python-xray-argo"
    echo -e "${BLUE}Script:${NC}  https://github.com/byJoey/free-vps-py"
    echo -e "${BLUE}TG group:${NC} https://t.me/+ft-zI76oovgwNmRh"
    echo
    echo "Choose setup mode:"
    echo "  1) Quick mode – change UUID only"
    echo "  2) Full mode  – configure everything"
    read -p "Enter choice (1/2): " MODE
    case "$MODE" in
        1|2) echo "$MODE" ;;
        *)   log_error "Invalid choice"; exit 1 ;;
    esac
}

# --- quick mode ---------------------------------------------------
quick_mode() {
    local uuid
    read -p "Enter UUID (leave empty to auto-generate): " uuid
    [[ -z "$uuid" ]] && uuid=$(generate_uuid)
    log_ok "Using UUID: $uuid"

    sed -i "s/^UUID = .*/UUID = os.environ.get('UUID', '$uuid')/" app.py
    sed -i "s/^CFIP = .*/CFIP = os.environ.get('CFIP', 'joeyblog.net')/" app.py
}

# --- full mode ----------------------------------------------------
full_mode() {
    local val
    read -p "Enter UUID (leave empty to auto-generate): " val
    [[ -z "$val" ]] && val=$(generate_uuid)
    sed -i "s/^UUID = .*/UUID = os.environ.get('UUID', '$val')/" app.py

    read -p "Node name (leave empty to keep current): " val
    [[ -n "$val" ]] && sed -i "s/^NAME = .*/NAME = os.environ.get('NAME', '$val')/" app.py

    read -p "Server port (leave empty to keep current): " val
    [[ -n "$val" ]] && sed -i "s/^PORT = int.*/PORT = int(os.environ.get('SERVER_PORT') or os.environ.get('PORT') or $val)/" app.py

    read -p "CDN IP/domain (default joeyblog.net): " val
    [[ -z "$val" ]] && val="joeyblog.net"
    sed -i "s/^CFIP = .*/CFIP = os.environ.get('CFIP', '$val')/" app.py

    read -p "CDN port (leave empty to keep current): " val
    [[ -n "$val" ]] && sed -i "s/^CFPORT = .*/CFPORT = int(os.environ.get('CFPORT', '$val'))/" app.py

    read -p "Argo port (leave empty to keep current): " val
    [[ -n "$val" ]] && sed -i "s/^ARGO_PORT = .*/ARGO_PORT = int(os.environ.get('ARGO_PORT', '$val'))/" app.py

    read -p "Subscription path (leave empty to keep current): " val
    [[ -n "$val" ]] && sed -i "s|^SUB_PATH = .*|SUB_PATH = os.environ.get('SUB_PATH', '$val')|" app.py
}

# --- backup -------------------------------------------------------
backup_app() {
    cp -a app.py app.py.backup
    log_ok "Backed up app.py -> app.py.backup"
}

# --- start service ------------------------------------------------
start_service() {
    log_info "Starting service in background ..."
    nohup python3 app.py > app.log 2>&1 &
    PID=$!
    log_ok "Service PID: $PID"
    sleep 10
    if kill -0 "$PID" 2>/dev/null; then
        log_ok "Service is running"
    else
        log_error "Service failed to start – check app.log"
        exit 1
    fi
    echo "$PID"
}

# --- print summary ------------------------------------------------
print_summary() {
    local pid=$1
    local port
    local uuid
    local subpath
    port=$(grep -m1 "^PORT = int" app.py | grep -oE '[0-9]+' | tail -1)
    uuid=$(grep -m1 "^UUID = " app.py | head -1 | cut -d"'" -f4)
    subpath=$(grep -m1 "^SUB_PATH = " app.py | cut -d"'" -f4)

    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}         Deployment finished!           ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "Service PID : ${BLUE}$pid${NC}"
    echo -e "Port        : ${BLUE}$port${NC}"
    echo -e "UUID        : ${BLUE}$uuid${NC}"
    echo -e "Sub path    : ${BLUE}/$subpath${NC}"
    echo
    echo -e "Local panel : ${GREEN}http://localhost:$port${NC}"
    echo -e "Local sub   : ${GREEN}http://localhost:$port/$subpath${NC}"
    echo
    echo -e "Log file    : ${YELLOW}$(pwd)/app.log${NC}"
    echo -e "Stop        : ${YELLOW}kill $pid${NC}"
    echo
}

# ------------------------------------------------------------------
# -------------------------- main flow -----------------------------
# ------------------------------------------------------------------
clear
MODE=$(select_mode)

# 1. ensure system packages
install_system_deps

# 2. clone / update repo
PROJECT_DIR=$(clone_repo)
cd "$PROJECT_DIR"

# 3. install python deps
install_python_deps requirements.txt

# 4. sanity check
[[ -f app.py ]] || { log_error "app.py not found"; exit 1; }

# 5. backup
backup_app

# 6. configure
case "$MODE" in
    1) quick_mode ;;
    2) full_mode ;;
esac

# 7. start
PID=$(start_service)

# 8. summary
print_summary "$PID"
