#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Database Backup & Offsite Cloud Archival Script
# ==============================================================================
# Functionality:
# 1. Dumps database (MariaDB/MySQL or PostgreSQL) using compressed format.
# 2. Validates backup file integrity and non-zero size.
# 3. Retains 7 days of local rolling backups and prunes older archives.
# 4. Encrypts dump using OpenSSL AES-256-CBC (PBKDF2).
# 5. Uploads encrypted backup to Google Cloud Storage (GCS) bucket.
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration & Parameter Defaults
# ------------------------------------------------------------------------------
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load environment variables if .env exists
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

CONTAINER_NAME="${CONTAINER_DB_NAME:-openmrs-db}"
DB_NAME="${MYSQL_DATABASE:-${POSTGRES_DB:-openmrs}}"
DB_USER="${MYSQL_USER:-${POSTGRES_USER:-openmrs_user}}"
DB_PASS="${MYSQL_PASSWORD:-${POSTGRES_PASSWORD:-}}"
ROOT_PASS="${MYSQL_ROOT_PASSWORD:-}"
BACKUP_DIR="${LOCAL_BACKUP_DIR:-/var/backups/openmrs}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
GCS_BUCKET="${GCS_BUCKET_NAME:-}"
ENCRYPTION_KEY="${BACKUP_ENCRYPTION_PASSPHRASE:-}"

BACKUP_FILENAME="openmrs_db_${TIMESTAMP}.sql.gz"
RAW_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
ENCRYPTED_BACKUP_PATH="${RAW_BACKUP_PATH}.enc"

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------
log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] $1"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $1" >&2
}

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
mkdir -p "${BACKUP_DIR}"

log_info "Starting OpenMRS database backup..."
log_info "Target database: '${DB_NAME}', container: '${CONTAINER_NAME}'"

# Verify Docker container is running
if ! docker ps --format '{{.Names}}' | grep -Eq "^${CONTAINER_NAME}\$"; then
    log_error "Database container '${CONTAINER_NAME}' is not running. Aborting backup."
    exit 1
fi

# ------------------------------------------------------------------------------
# Step 1: Execute Database Dump inside Container
# ------------------------------------------------------------------------------
log_info "Generating database dump..."
if docker exec "${CONTAINER_NAME}" which mariadb-dump &>/dev/null || docker exec "${CONTAINER_NAME}" which mysqldump &>/dev/null; then
    DUMP_CMD="mysqldump"
    if docker exec "${CONTAINER_NAME}" which mariadb-dump &>/dev/null; then
        DUMP_CMD="mariadb-dump"
    fi
    AUTH_FLAG="-p${ROOT_PASS:-${DB_PASS}}"
    docker exec "${CONTAINER_NAME}" "${DUMP_CMD}" -u root ${AUTH_FLAG} --all-databases | gzip > "${RAW_BACKUP_PATH}"
elif docker exec "${CONTAINER_NAME}" which pg_dump &>/dev/null; then
    docker exec -e PGPASSWORD="${DB_PASS}" "${CONTAINER_NAME}" pg_dump -U "${DB_USER}" -d "${DB_NAME}" | gzip > "${RAW_BACKUP_PATH}"
else
    log_error "Neither mysqldump nor pg_dump found in container."
    exit 2
fi

# Verify dump is not empty
DUMP_SIZE=$(stat -c%s "${RAW_BACKUP_PATH}" 2>/dev/null || stat -f%z "${RAW_BACKUP_PATH}")
if [[ "${DUMP_SIZE}" -le 100 ]]; then
    log_error "Backup file is unexpectedly small (${DUMP_SIZE} bytes). Possible dump corruption."
    rm -f "${RAW_BACKUP_PATH}"
    exit 3
fi
log_info "Compressed dump size: $(numfmt --to=iec --suffix=B "${DUMP_SIZE}" 2>/dev/null || echo "${DUMP_SIZE} bytes")"

# ------------------------------------------------------------------------------
# Step 2: Encrypt Backup (AES-256-CBC)
# ------------------------------------------------------------------------------
UPLOAD_TARGET_PATH="${RAW_BACKUP_PATH}"

if [[ -n "${ENCRYPTION_KEY}" && "${ENCRYPTION_KEY}" != "CHANGE_ME_TO_A_SECURE_BACKUP_PASSPHRASE" ]]; then
    log_info "Encrypting backup with AES-256-CBC (PBKDF2)..."
    openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
        -in "${RAW_BACKUP_PATH}" \
        -out "${ENCRYPTED_BACKUP_PATH}" \
        -pass pass:"${ENCRYPTION_KEY}"
    
    sha256sum "${ENCRYPTED_BACKUP_PATH}" > "${ENCRYPTED_BACKUP_PATH}.sha256"
    UPLOAD_TARGET_PATH="${ENCRYPTED_BACKUP_PATH}"
    log_info "Encrypted file generated: ${ENCRYPTED_BACKUP_PATH}"
else
    log_info "No backup encryption passphrase configured. Skipping client-side encryption."
    sha256sum "${RAW_BACKUP_PATH}" > "${RAW_BACKUP_PATH}.sha256"
fi

# ------------------------------------------------------------------------------
# Step 3: Offsite Upload to Google Cloud Storage (GCS)
# ------------------------------------------------------------------------------
if [[ -n "${GCS_BUCKET}" && "${GCS_BUCKET}" != "openmrs-gcp-pilot-backups" ]]; then
    log_info "Uploading backup to Google Cloud Storage bucket: gs://${GCS_BUCKET}/backups/..."
    
    if command -v gcloud &>/dev/null; then
        gcloud storage cp "${UPLOAD_TARGET_PATH}" "gs://${GCS_BUCKET}/backups/"
        gcloud storage cp "${UPLOAD_TARGET_PATH}.sha256" "gs://${GCS_BUCKET}/backups/"
        log_info "GCS upload completed via gcloud storage."
    elif command -v gsutil &>/dev/null; then
        gsutil cp "${UPLOAD_TARGET_PATH}" "gs://${GCS_BUCKET}/backups/"
        gsutil cp "${UPLOAD_TARGET_PATH}.sha256" "gs://${GCS_BUCKET}/backups/"
        log_info "GCS upload completed via gsutil."
    else
        log_error "Neither 'gcloud' nor 'gsutil' CLI is installed. Cloud upload skipped."
    fi
else
    log_info "GCS bucket not specified or left at default placeholder. Cloud upload skipped."
fi

# ------------------------------------------------------------------------------
# Step 4: Prune Local Backups Older than Retention Window
# ------------------------------------------------------------------------------
log_info "Pruning local backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -maxdepth 1 -name "openmrs_db_*" -type f -mtime +"${RETENTION_DAYS}" -exec rm -vf {} +

log_info "Backup process completed successfully."
exit 0
