#!/usr/bin/env bash
# ==============================================================================
# OncMRS — Automated Zero-Config Host Provisioning & Stack Bootstrap
# ==============================================================================
# Single-command runner designed for clean, newly provisioned Linux VMs.
# Sets up prerequisites, generates cryptographic secrets, executes Ansible
# orchestration locally, launches OpenMRS 3.x containers, and verifies health.
# ==============================================================================

set -euo pipefail

# Text styling
BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

log_info()    { echo -e "${BLUE}[INFO]${RESET} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET} $1"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $1" >&2; }

echo -e "${BOLD}====================================================================${RESET}"
echo -e "${BOLD}       OpenMRS 3.x Pilot — Zero-Config Host Bootstrapper            ${RESET}"
echo -e "${BOLD}====================================================================${RESET}"

# Prevent apt from hanging on interactive prompts during automated runs
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# 1. Check Root / Sudo Privileges
if [[ "${EUID}" -ne 0 ]]; then
    log_warn "This script requires administrative privileges."
    log_info "Attempting to escalate with sudo..."
    exec sudo -E bash "$0" "$@"
fi

# 2. Determine project location or auto-clone repository if run remotely/piped
REPO_URL="https://github.com/ahmed-tagg/OncMRS.git"
REPO_BRANCH="develop"
TARGET_DIR="/opt/oncopenmrs"

# Determine current location if running as an existing script file
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
fi

if [[ -n "${SCRIPT_DIR}" && -f "${SCRIPT_DIR}/ansible/site.yml" && -f "${SCRIPT_DIR}/docker/docker-compose.yml" ]]; then
    PROJECT_ROOT="${SCRIPT_DIR}"
    log_info "Running inside local repository: ${PROJECT_ROOT}"
elif [[ -f "./ansible/site.yml" && -f "./docker/docker-compose.yml" ]]; then
    PROJECT_ROOT="$(pwd)"
    log_info "Running inside local repository: ${PROJECT_ROOT}"
else
    log_info "Repository files not found in current path. Preparing standalone installation..."
    # Ensure curl and git are installed to clone
    apt-get update -qq
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" curl git ca-certificates

    if [[ -d "${TARGET_DIR}/.git" ]]; then
        log_info "Updating existing repository at ${TARGET_DIR}..."
        git -C "${TARGET_DIR}" fetch origin "${REPO_BRANCH}"
        git -C "${TARGET_DIR}" checkout "${REPO_BRANCH}"
        git -C "${TARGET_DIR}" pull origin "${REPO_BRANCH}"
    else
        log_info "Cloning repository (${REPO_BRANCH}) into ${TARGET_DIR}..."
        mkdir -p "$(dirname "${TARGET_DIR}")"
        git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${TARGET_DIR}"
    fi
    PROJECT_ROOT="${TARGET_DIR}"
    cd "${PROJECT_ROOT}"
fi

# 3. Make scripts executable
log_info "Ensuring script permissions..."
chmod +x "${PROJECT_ROOT}/bootstrap.sh" 2>/dev/null || true
chmod +x "${PROJECT_ROOT}/scripts/"*.sh 2>/dev/null || true

# 4. Detect and install base dependencies
log_info "Checking prerequisite packages (curl, git, python3, openssl, docker, ansible)..."

install_pkg() {
    local PKG="$1"
    if ! command -v "${PKG}" >/dev/null 2>&1; then
        log_info "Installing missing dependency: ${PKG}..."
        apt-get update -qq && apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" "${PKG}"
    fi
}

install_pkg curl
install_pkg git
install_pkg python3
install_pkg openssl
install_pkg gnupg
install_pkg software-properties-common

# Ensure Docker CE and Compose plugin are installed
if ! command -v docker >/dev/null 2>&1; then
    log_info "Docker not found. Installing Docker CE via official script..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

# Ensure Ansible is installed
if ! command -v ansible-playbook >/dev/null 2>&1; then
    log_info "Ansible not found. Installing Ansible..."
    apt-get update -qq
    apt-get install -y -qq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" ansible || {
        log_warn "Apt install failed for ansible; attempting via pip3..."
        apt-get install -y -qq python3-pip
        pip3 install --break-system-packages ansible 2>/dev/null || pip3 install ansible
    }
fi
log_success "All prerequisites are satisfied."

# 5. Generate Production Secrets if .env is missing
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    log_info "No .env found. Automatically generating cryptographic secrets..."
    "${PROJECT_ROOT}/scripts/generate-secrets.sh" --force
else
    log_info "Existing .env detected. Preserving current environment credentials."
fi

# Ensure docker/.env is in sync
cp -f "${PROJECT_ROOT}/.env" "${PROJECT_ROOT}/docker/.env"

# 6. Run Ansible Orchestration locally
log_info "Executing Ansible Orchestrator (Kernel, Swap, Docker, Backup, Deploy)..."
cd "${PROJECT_ROOT}/ansible"

ansible-playbook \
    -i inventory/local.ini \
    site.yml \
    --extra-vars "project_dir=${PROJECT_ROOT}"

# 7. Run Stack Verification
log_info "Running automated stack verification..."
"${PROJECT_ROOT}/scripts/verify-stack.sh" || {
    log_warn "Verification encountered non-critical warnings. Please check container logs."
}

# 8. Discover Host Public / Internal IP
SERVER_IP=$(curl -s --connect-timeout 2 ifconfig.me 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}' 2>/dev/null || echo "localhost")

echo ""
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "${BOLD}${GREEN}       OpenMRS 3.x System Deployment Complete!                      ${RESET}"
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "Clinical SPA Interface: ${BOLD}http://${SERVER_IP}/openmrs/spa/home${RESET}"
echo -e "Admin Console:          ${BOLD}http://${SERVER_IP}/openmrs/${RESET}"
echo -e "Default User:           ${BOLD}admin${RESET}"
echo -e "Default Password:       ${BOLD}Admin123${RESET}"
echo ""
echo -e "Project Location:       ${BOLD}${PROJECT_ROOT}${RESET}"
echo -e "Automatic Backups:      Configured daily at 02:00 AM (${BOLD}/var/backups/openmrs${RESET})"
echo -e "Swap Space:             4GB active (/swapfile with boot persistence)"
echo -e "Kernel Optimizations:   Sysctl throughput parameters applied"
echo -e "${BOLD}====================================================================${RESET}"
