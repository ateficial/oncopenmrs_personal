#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Task 1.2: GCP VPC Firewall & Hardening Script
# ==============================================================================
# Configures ingress firewall rules on Google Cloud Platform:
# 1. Allows HTTP (80) & HTTPS (443) from any source (0.0.0.0/0).
# 2. Restricts SSH (22) to Google IAP tunneling (35.235.240.0/20) and/or Admin IP.
# 3. Explicitly DENIES external ingress to ports 8080 (Tomcat), 5432 (Postgres), 8000.
#
# Usage:
#   export GCP_PROJECT_ID="your-project-id"
#   export ADMIN_IP_CIDR="203.0.113.50/32"  # Optional
#   ./scripts/configure-firewall.sh
# ==============================================================================

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-}"
NETWORK="${VPC_NETWORK:-default}"
TARGET_TAG="openmrs-server"
ADMIN_CIDR="${ADMIN_IP_CIDR:-}"

# Google Cloud Identity-Aware Proxy (IAP) CIDR block for secure SSH
IAP_CIDR="35.235.240.0/20"

log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] $1"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $1" >&2
}

if ! command -v gcloud &>/dev/null; then
    log_error "'gcloud' CLI is not installed. Please run this in GCP Cloud Shell or with Google Cloud SDK."
    exit 1
fi

if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "${PROJECT_ID}" ]]; then
    log_error "GCP Project ID is required. Set GCP_PROJECT_ID environment variable."
    exit 1
fi

# Build SSH source ranges
SSH_SOURCES="${IAP_CIDR}"
if [[ -n "${ADMIN_CIDR}" ]]; then
    SSH_SOURCES="${SSH_SOURCES},${ADMIN_CIDR}"
fi

log_info "============================================================"
log_info "Configuring GCP VPC Firewall Rules for OpenMRS Pilot"
log_info "Project ID:      ${PROJECT_ID}"
log_info "Network:         ${NETWORK}"
log_info "Target Tag:      ${TARGET_TAG}"
log_info "Allowed Web:     TCP 80, 443 (0.0.0.0/0)"
log_info "Allowed SSH:     TCP 22 (${SSH_SOURCES})"
log_info "Blocked Ports:   TCP 8080, 5432, 8000 (0.0.0.0/0)"
log_info "============================================================"

read -rp "Apply these firewall rules to project '${PROJECT_ID}'? [y/N]: " confirm
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    log_info "Firewall configuration aborted."
    exit 0
fi

# 1. Allow Web Ingress (HTTP / HTTPS)
log_info "1/3 Creating/Updating firewall rule: allow-openmrs-web..."
gcloud compute firewall-rules create allow-openmrs-web \
    --project="${PROJECT_ID}" \
    --network="${NETWORK}" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:80,tcp:443 \
    --target-tags="${TARGET_TAG}" \
    --source-ranges=0.0.0.0/0 \
    --description="Allow public HTTP and HTTPS traffic to OpenMRS NGINX proxy" 2>/dev/null || \
gcloud compute firewall-rules update allow-openmrs-web \
    --project="${PROJECT_ID}" \
    --rules=tcp:80,tcp:443 \
    --source-ranges=0.0.0.0/0

# 2. Allow SSH (Restricted to IAP / Admin CIDR)
log_info "2/3 Creating/Updating firewall rule: allow-openmrs-ssh..."
gcloud compute firewall-rules create allow-openmrs-ssh \
    --project="${PROJECT_ID}" \
    --network="${NETWORK}" \
    --direction=INGRESS \
    --priority=1000 \
    --action=ALLOW \
    --rules=tcp:22 \
    --target-tags="${TARGET_TAG}" \
    --source-ranges="${SSH_SOURCES}" \
    --description="Allow restricted SSH access via Google IAP and Admin CIDR" 2>/dev/null || \
gcloud compute firewall-rules update allow-openmrs-ssh \
    --project="${PROJECT_ID}" \
    --rules=tcp:22 \
    --source-ranges="${SSH_SOURCES}"

# 3. Explicitly Deny Direct Internal Ingress
log_info "3/3 Creating/Updating firewall rule: deny-openmrs-internal-ports..."
gcloud compute firewall-rules create deny-openmrs-internal-ports \
    --project="${PROJECT_ID}" \
    --network="${NETWORK}" \
    --direction=INGRESS \
    --priority=900 \
    --action=DENY \
    --rules=tcp:8080,tcp:5432,tcp:8000 \
    --target-tags="${TARGET_TAG}" \
    --source-ranges=0.0.0.0/0 \
    --description="Explicitly block public access to internal Tomcat, Postgres, and dev ports" 2>/dev/null || \
gcloud compute firewall-rules update deny-openmrs-internal-ports \
    --project="${PROJECT_ID}" \
    --rules=tcp:8080,tcp:5432,tcp:8000 \
    --source-ranges=0.0.0.0/0

log_info "VPC Firewall rules successfully configured and hardened."
