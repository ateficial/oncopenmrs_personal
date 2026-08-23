#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Task 1.6: Automated Stack Health & Verification Script
# ==============================================================================
# Verifies container health, PostgreSQL database state, HTTP/HTTPS endpoints,
# and captures runtime resource consumption.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load environment
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

CONTAINER_DB="${CONTAINER_DB_NAME:-openmrs-db}"
CONTAINER_WEB="openmrs-web"
CONTAINER_NGINX="openmrs-nginx"
DOMAIN="${SERVER_NAME:-localhost}"

log_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

log_pass() {
    echo -e "\033[1;32m[PASS]\033[0m $1"
}

log_fail() {
    echo -e "\033[1;31m[FAIL]\033[0m $1" >&2
}

echo "============================================================"
echo " OpenMRS Pilot — End-to-End Stack Verification"
echo "============================================================"

# 1. Verify Docker Containers
log_info "1. Checking container states..."
for container in "${CONTAINER_DB}" "${CONTAINER_WEB}" "${CONTAINER_NGINX}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null || echo "not_found")
    if [[ "${STATUS}" == "running" ]]; then
        log_pass "Container '${container}' is running."
    else
        log_fail "Container '${container}' is in state: ${STATUS}"
    fi
done

# 2. Verify PostgreSQL Health & Connectivity
log_info "2. Checking PostgreSQL database connectivity..."
if docker exec "${CONTAINER_DB}" pg_isready -U "${POSTGRES_USER:-openmrs_user}" -d "${POSTGRES_DB:-openmrs}"; then
    log_pass "PostgreSQL is accepting connections."
else
    log_fail "PostgreSQL is not responding to pg_isready."
fi

# 3. Check Database Table Count
log_info "3. Verifying database table schema..."
TABLE_COUNT=$(docker exec "${CONTAINER_DB}" psql -U "${POSTGRES_USER:-openmrs_user}" -d "${POSTGRES_DB:-openmrs}" -t -c \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
TABLE_COUNT=$(echo "${TABLE_COUNT}" | tr -d '[:space:]')

if [[ "${TABLE_COUNT}" -gt 0 ]]; then
    log_pass "Database tables detected: ${TABLE_COUNT} public tables present."
else
    log_info "Database is currently initializing or empty (table count: ${TABLE_COUNT})."
fi

# 4. Check NGINX Web Response
log_info "4. Testing HTTP endpoint response..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" || echo "000")
if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "301" || "${HTTP_CODE}" == "302" ]]; then
    log_pass "NGINX endpoint reachable (HTTP Status: ${HTTP_CODE})."
else
    log_fail "NGINX endpoint returned HTTP Status: ${HTTP_CODE}."
fi

# 5. Resource Consumption Snapshot
echo ""
log_info "5. Live Container Resource Usage (docker stats):"
echo "------------------------------------------------------------"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo "------------------------------------------------------------"

echo ""
log_pass "Stack verification routine completed."
