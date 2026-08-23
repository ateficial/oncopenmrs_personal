#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Secure Secret & Environment Generator
# ==============================================================================
# Generates high-entropy cryptographic secrets and writes them to .env without
# leaking sensitive strings to stdout or terminal logs.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
ENV_FILE="${PROJECT_ROOT}/.env"
EXAMPLE_FILE="${PROJECT_ROOT}/.env.example"

if [[ ! -f "${EXAMPLE_FILE}" ]]; then
    echo "[ERROR] .env.example not found at ${EXAMPLE_FILE}" >&2
    exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
    echo "[WARNING] .env file already exists."
    read -rp "Overwrite existing .env file with newly generated secrets? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Secret generation aborted. Existing .env preserved."
        exit 0
    fi
fi

echo "[INFO] Generating cryptographically random passwords..."

# Generate secure random alphanumeric strings (avoiding sed delimiter collision)
generate_random_secret() {
    openssl rand -hex 24
}

POSTGRES_PASS=$(generate_random_secret)
ADMIN_PASS=$(generate_random_secret)
BACKUP_KEY=$(generate_random_secret)

cp "${EXAMPLE_FILE}" "${ENV_FILE}"

# Replace placeholder tokens safely
sed -i.bak \
    -e "s|POSTGRES_PASSWORD=CHANGE_ME_TO_A_SECURE_POSTGRES_PASSWORD|POSTGRES_PASSWORD=${POSTGRES_PASS}|g" \
    -e "s|OPENMRS_DB_PASSWORD=CHANGE_ME_TO_A_SECURE_POSTGRES_PASSWORD|OPENMRS_DB_PASSWORD=${POSTGRES_PASS}|g" \
    -e "s|OPENMRS_ADMIN_PASSWORD=Admin123!_CHANGE_ME|OPENMRS_ADMIN_PASSWORD=${ADMIN_PASS}|g" \
    -e "s|BACKUP_ENCRYPTION_PASSPHRASE=CHANGE_ME_TO_A_SECURE_BACKUP_PASSPHRASE|BACKUP_ENCRYPTION_PASSPHRASE=${BACKUP_KEY}|g" \
    "${ENV_FILE}"

rm -f "${ENV_FILE}.bak"
chmod 600 "${ENV_FILE}"

echo "[SUCCESS] '.env' has been generated with secure permissions (chmod 600)."
echo "[INFO] Passwords were written directly to ${ENV_FILE} without being printed to logs."
