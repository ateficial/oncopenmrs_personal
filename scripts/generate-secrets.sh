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

FORCE_OVERWRITE=false
if [[ "${1:-}" == "-f" || "${1:-}" == "--force" ]]; then
    FORCE_OVERWRITE=true
fi

if [[ -f "${ENV_FILE}" && "${FORCE_OVERWRITE}" != "true" ]]; then
    echo "[WARNING] .env file already exists."
    read -rp "Overwrite existing .env file with newly generated secrets? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        echo "[INFO] Secret generation aborted. Existing .env preserved."
        exit 0
    fi
fi

echo "[INFO] Generating cryptographically random passwords..."

generate_random_secret() {
    openssl rand -hex 24 2>/dev/null || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

DB_USER_PASS=$(generate_random_secret)
DB_ROOT_PASS=$(generate_random_secret)
BACKUP_KEY=$(generate_random_secret)

cp "${EXAMPLE_FILE}" "${ENV_FILE}"

# Replace placeholder tokens safely
sed -i.bak \
    -e "s|MYSQL_PASSWORD=CHANGE_ME_TO_A_SECURE_MYSQL_PASSWORD|MYSQL_PASSWORD=${DB_USER_PASS}|g" \
    -e "s|MYSQL_ROOT_PASSWORD=CHANGE_ME_TO_A_SECURE_ROOT_PASSWORD|MYSQL_ROOT_PASSWORD=${DB_ROOT_PASS}|g" \
    -e "s|BACKUP_ENCRYPTION_PASSPHRASE=CHANGE_ME_TO_A_SECURE_BACKUP_PASSPHRASE|BACKUP_ENCRYPTION_PASSPHRASE=${BACKUP_KEY}|g" \
    "${ENV_FILE}"

rm -f "${ENV_FILE}.bak"
chmod 600 "${ENV_FILE}" 2>/dev/null || true

echo "[SUCCESS] '.env' has been generated with secure permissions."
echo "[INFO] Passwords were written directly to ${ENV_FILE} without being printed to logs."
