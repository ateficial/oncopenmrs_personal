#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Task 1.1: GCP Compute Instance Provisioning Script
# ==============================================================================
# Provisions an e2-standard-4 instance on Google Cloud Platform with Ubuntu 22.04
# and 100GB SSD persistent storage.
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export GCP_ZONE="us-central1-a"
#   ./scripts/provision-gcp.sh
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Default Parameters
# ------------------------------------------------------------------------------
INSTANCE_NAME="${INSTANCE_NAME:-openmrs-pilot-vm}"
PROJECT_ID="${GCP_PROJECT_ID:-}"
ZONE="${GCP_ZONE:-us-central1-a}"
MACHINE_TYPE="e2-standard-4"
BOOT_DISK_SIZE="100GB"
BOOT_DISK_TYPE="pd-ssd"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
NETWORK_TAGS="openmrs-server,http-server,https-server"

log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] $1"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $1" >&2
}

if ! command -v gcloud &>/dev/null; then
    log_error "'gcloud' CLI is not installed. Please install the Google Cloud SDK or run this in GCP Cloud Shell."
    exit 1
fi

if [[ -z "${PROJECT_ID}" ]]; then
    # Try getting default project from gcloud config
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "${PROJECT_ID}" ]]; then
    log_error "GCP Project ID is required. Set GCP_PROJECT_ID environment variable."
    exit 1
fi

log_info "============================================================"
log_info "Provisioning OpenMRS Pilot VM on GCP Compute Engine"
log_info "Instance Name: ${INSTANCE_NAME}"
log_info "Project ID:    ${PROJECT_ID}"
log_info "Zone:          ${ZONE}"
log_info "Machine Type:  ${MACHINE_TYPE} (4 vCPU, 16 GB RAM)"
log_info "Disk:          ${BOOT_DISK_SIZE} ${BOOT_DISK_TYPE}"
log_info "OS Image:      Ubuntu 22.04 LTS"
log_info "Network Tags:  ${NETWORK_TAGS}"
log_info "============================================================"

# Confirm before proceeding
read -rp "Proceed with VM provisioning? [y/N]: " confirm
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "Provisioning aborted by user."
    exit 0
fi

log_info "Executing gcloud compute instances create..."

gcloud compute instances create "${INSTANCE_NAME}" \
    --project="${PROJECT_ID}" \
    --zone="${ZONE}" \
    --machine-type="${MACHINE_TYPE}" \
    --image-family="${IMAGE_FAMILY}" \
    --image-project="${IMAGE_PROJECT}" \
    --boot-disk-size="${BOOT_DISK_SIZE}" \
    --boot-disk-type="${BOOT_DISK_TYPE}" \
    --boot-disk-auto-delete \
    --maintenance-policy=MIGRATE \
    --restart-on-failure \
    --tags="${NETWORK_TAGS}" \
    --metadata=enable-oslogin=TRUE

log_info "Instance '${INSTANCE_NAME}' provisioned successfully."

# Retrieve external IP address
EXTERNAL_IP=$(gcloud compute instances describe "${INSTANCE_NAME}" \
    --project="${PROJECT_ID}" \
    --zone="${ZONE}" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

log_info "Public IP Address: ${EXTERNAL_IP}"
log_info "You can now update 'ansible/inventory.ini' with IP: ${EXTERNAL_IP}"
