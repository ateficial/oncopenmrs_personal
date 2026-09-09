#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Remote Single-Command Deployment Runner
# ==============================================================================
# Deploys OpenMRS 3.x and provisions a remote VM from your workstation with one command:
#   ./scripts/deploy-remote.sh <TARGET_IP> [SSH_USER] [SSH_KEY]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

TARGET_IP="${1:-}"
SSH_USER="${2:-ubuntu}"
SSH_KEY="${3:-${HOME}/.ssh/id_rsa}"

if [[ -z "${TARGET_IP}" ]]; then
    echo "Usage: $0 <TARGET_IP> [SSH_USER] [SSH_KEY]"
    echo "Example: $0 34.123.45.67 ubuntu ~/.ssh/id_rsa"
    exit 1
fi

echo "===================================================================="
echo " Deploying OpenMRS 3.x to Remote VM: ${TARGET_IP}"
echo " User: ${SSH_USER} | Key: ${SSH_KEY}"
echo "===================================================================="

# 1. Test SSH connectivity
echo "[INFO] Testing SSH connectivity to ${SSH_USER}@${TARGET_IP}..."
if ! ssh -i "${SSH_KEY}" -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=8 "${SSH_USER}@${TARGET_IP}" "echo OK" >/dev/null 2>&1; then
    echo "[ERROR] Cannot reach ${SSH_USER}@${TARGET_IP} via SSH."
    echo "[HINT] Ensure your SSH public key is in ~/.ssh/authorized_keys on the target VM."
    exit 1
fi
echo "[SUCCESS] SSH connection verified."

# 2. Sync project files to remote host
echo "[INFO] Synchronizing project files to remote host..."
rsync -avz --exclude '.git' --exclude 'rotated_secrets' --exclude '.env' \
    -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no" \
    "${PROJECT_ROOT}/" "${SSH_USER}@${TARGET_IP}:/tmp/oncopenmrs/"

# 3. Execute remote bootstrap
echo "[INFO] Executing remote zero-config bootstrap..."
ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -t "${SSH_USER}@${TARGET_IP}" \
    "sudo cp -r /tmp/oncopenmrs /opt/oncopenmrs && cd /opt/oncopenmrs && sudo bash bootstrap.sh"

echo "===================================================================="
echo "[SUCCESS] Remote deployment finished successfully!"
echo "Access the OpenMRS 3.x SPA at: http://${TARGET_IP}/openmrs/spa/home"
echo "===================================================================="
