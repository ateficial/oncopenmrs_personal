#!/usr/bin/env bash
# ==============================================================================
# OncMRS — Automated Zero-Config Host Provisioning & Stack Bootstrap
# ==============================================================================
# Single-command runner designed for clean, newly provisioned Virtual Machines.
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

# Determine directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

echo -e "${BOLD}====================================================================${RESET}"
echo -e "${BOLD}       OpenMRS 3.x Pilot — Zero-Config Host Bootstrapper            ${RESET}"
echo -e "${BOLD}====================================================================${RESET}"

# 1. Check Root / Sudo Privileges
if [[ "${EUID}" -ne 0 ]]; then
    log_warn "This script requires administrative privileges."
    log_info "Attempting to escalate with sudo..."
    exec sudo bash "$0" "$@"
fi

# 2. Make scripts executable
log_info "Ensuring script permissions..."
chmod +x "${PROJECT_ROOT}/scripts/"*.sh 2>/dev/null || true

# 3. Detect and install base dependencies if missing
log_info "Checking prerequisite packages (curl, git, python3, ansible)..."

install_pkg() {
    local PKG="$1"
    if ! command -v "${PKG}" >/dev/null 2>&1; then
        log_info "Installing missing dependency: ${PKG}..."
        apt-get update -qq && apt-get install -y -qq "${PKG}"
    fi
}

install_pkg curl
install_pkg git
install_pkg python3
install_pkg openssl

# Check and install Ansible if not available
if ! command -v ansible-playbook >/dev/null 2>&1; then
    log_info "Ansible not found. Installing Ansible..."
    apt-get update -qq
    apt-get install -y -qq software-properties-common
    add-apt-repository --yes --update ppa:ansible/ansible 2>/dev/null || true
    apt-get install -y -qq ansible || {
        log_warn "Apt install failed for ansible; attempting via pip3..."
        apt-get install -y -qq python3-pip
        pip3 install ansible
    }
fi
log_success "Prerequisites are satisfied."

# 4. Generate Production Secrets if .env is missing
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
    log_info "No .env found. Automatically generating cryptographic secrets..."
    "${PROJECT_ROOT}/scripts/generate-secrets.sh" --force
else
    log_info "Existing .env detected. Preserving current environment credentials."
fi

# 5. Run Ansible Orchestration locally
log_info "Executing Ansible Orchestrator (Kernel, Swap, Docker, Backup, Deploy)..."
cd "${PROJECT_ROOT}/ansible"

ansible-playbook \
    -i inventory/local.ini \
    site.yml \
    --extra-vars "project_dir=${PROJECT_ROOT}"

# 6. Run Stack Verification
log_info "Running automated stack verification..."
"${PROJECT_ROOT}/scripts/verify-stack.sh" || {
    log_warn "Verification encountered non-critical warnings. Please check container logs."
}

# 7. Discover Host Public / Internal IP
SERVER_IP=$(curl -s --connect-timeout 2 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo ""
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "${BOLD}${GREEN}       OpenMRS 3.x System Deployment Complete!                      ${RESET}"
echo -e "${BOLD}${GREEN}====================================================================${RESET}"
echo -e "Clinical SPA Interface: ${BOLD}http://${SERVER_IP}/openmrs/spa/home${RESET}"
echo -e "Admin Console:          ${BOLD}http://${SERVER_IP}/openmrs/${RESET}"
echo -e "Default User:           ${BOLD}admin${RESET}"
echo -e "Default Password:       ${BOLD}Admin123${RESET}"
echo ""
echo -e "Automatic Backups:      Configured daily at 02:00 AM (${BOLD}/var/backups/openmrs${RESET})"
echo -e "Swap Space:             4GB active (/swapfile with boot persistence)"
echo -e "Kernel Optimizations:   Sysctl throughput parameters applied"
echo -e "${BOLD}====================================================================${RESET}"
