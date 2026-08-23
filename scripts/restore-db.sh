#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Database Restore & Disaster Recovery Script
# ==============================================================================
# Usage:
#   ./scripts/restore-db.sh /path/to/backup.dump
#   ./scripts/restore-db.sh /path/to/backup.dump.enc
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load environment variables
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

CONTAINER_NAME="${CONTAINER_DB_NAME:-openmrs-db}"
DB_NAME="${POSTGRES_DB:-openmrs}"
DB_USER="${POSTGRES_USER:-openmrs_user}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_PASSPHRASE:-}"

log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] $1"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $1" >&2
}

if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 <path_to_backup_file.dump | path_to_backup_file.dump.enc>"
    exit 1
fi

INPUT_FILE="$1"

if [[ ! -f "${INPUT_FILE}" ]]; then
    log_error "Backup file '${INPUT_FILE}' does not exist."
    exit 1
fi

RESTORE_TARGET="${INPUT_FILE}"
TEMP_DECRYPTED=""

# Decrypt if the file is encrypted (.enc)
if [[ "${INPUT_FILE}" == *.enc ]]; then
    log_info "Encrypted archive detected. Decrypting..."
    TEMP_DECRYPTED="/tmp/openmrs_restore_$(date +%s).dump"
    
    if [[ -z "${ENCRYPTION_KEY}" || "${ENCRYPTION_KEY}" == "CHANGE_ME_TO_A_SECURE_BACKUP_PASSPHRASE" ]]; then
        read -rsp "Enter backup decryption passphrase: " ENCRYPTION_KEY
        echo ""
    fi

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "${INPUT_FILE}" \
        -out "${TEMP_DECRYPTED}" \
        -pass pass:"${ENCRYPTION_KEY}"
    
    RESTORE_TARGET="${TEMP_DECRYPTED}"
    log_info "Decryption successful: ${TEMP_DECRYPTED}"
fi

cleanup() {
    if [[ -n "${TEMP_DECRYPTED}" && -f "${TEMP_DECRYPTED}" ]]; then
        log_info "Securely removing temporary decrypted dump..."
        rm -f "${TEMP_DECRYPTED}"
    fi
}
trap cleanup EXIT

# Verify Postgres container is running
if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    log_error "Database container '${CONTAINER_NAME}' is not running."
    exit 1
fi

log_info "Restoring PostgreSQL database '${DB_NAME}' from '${RESTORE_TARGET}'..."

# Copy dump into container /tmp and execute pg_restore
docker cp "${RESTORE_TARGET}" "${CONTAINER_NAME}:/tmp/restore.dump"

if docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-}" "${CONTAINER_NAME}" \
    pg_restore -U "${DB_USER}" -d "${DB_NAME}" --clean --if-exists --no-owner --no-privileges /tmp/restore.dump; then
    log_info "Database restore completed successfully."
else
    log_error "Database restore encountered errors (non-fatal warnings may have occurred)."
fi

docker exec "${CONTAINER_NAME}" rm -f /tmp/restore.dump

log_info "Disaster recovery restore finished."
