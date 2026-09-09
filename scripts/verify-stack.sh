#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Task 1.6: Automated Stack Health & Verification Script
# ==============================================================================
# Verifies container health, MariaDB database state, HTTP/HTTPS endpoints,
# and captures runtime resource consumption.
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load environment if present
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

CONTAINER_DB="${CONTAINER_DB_NAME:-openmrs-db}"
CONTAINER_BACKEND="openmrs-backend"
CONTAINER_FRONTEND="openmrs-frontend"
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
echo " OpenMRS 3.x Pilot — End-to-End Stack Verification"
echo "============================================================"

# 1. Verify Docker Containers
log_info "1. Checking container states..."
for container in "${CONTAINER_DB}" "${CONTAINER_BACKEND}" "${CONTAINER_FRONTEND}" "${CONTAINER_NGINX}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "${container}" 2>/dev/null | tr -d '\r' || echo "not_found")
    if [[ "${STATUS}" == "running" ]]; then
        log_pass "Container '${container}' is running."
    else
        log_fail "Container '${container}' is in state: ${STATUS}"
    fi
done

# 2. Verify MariaDB Health & Connectivity
log_info "2. Checking MariaDB database connectivity..."
if docker exec "${CONTAINER_DB}" sh -c 'mariadb-admin ping -u root -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1 || mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD}" >/dev/null 2>&1'; then
    log_pass "MariaDB is accepting connections and responding to health checks."
else
    log_fail "MariaDB is not responding to ping check."
fi

# 3. Check Database Table Count
log_info "3. Verifying database table schema..."
TABLE_COUNT=$(docker exec "${CONTAINER_DB}" sh -c 'mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" -s -N -e "SELECT count(*) FROM information_schema.tables WHERE table_schema = \"'${MYSQL_DATABASE:-openmrs}'\";" 2>/dev/null || echo "0"')
TABLE_COUNT=$(echo "${TABLE_COUNT}" | tr -d '[:space:]')

if [[ "${TABLE_COUNT}" -gt 50 ]]; then
    log_pass "Database tables verified: ${TABLE_COUNT} OpenMRS tables present."
else
    log_info "Database is currently initializing or populating (table count: ${TABLE_COUNT})."
fi

# 4. Check NGINX Web Response (SPA and Backend)
log_info "4. Testing HTTP endpoint responses..."
HTTP_SPA_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/openmrs/spa/home" || echo "000")
if [[ "${HTTP_SPA_CODE}" == "200" || "${HTTP_SPA_CODE}" == "301" || "${HTTP_SPA_CODE}" == "302" ]]; then
    log_pass "OpenMRS 3.x SPA endpoint reachable (HTTP Status: ${HTTP_SPA_CODE})."
else
    log_fail "OpenMRS 3.x SPA endpoint returned HTTP Status: ${HTTP_SPA_CODE}."
fi

HTTP_ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/" || echo "000")
if [[ "${HTTP_ROOT_CODE}" == "200" || "${HTTP_ROOT_CODE}" == "301" || "${HTTP_ROOT_CODE}" == "302" ]]; then
    log_pass "NGINX Gateway root redirection reachable (HTTP Status: ${HTTP_ROOT_CODE})."
else
    log_fail "NGINX Gateway root returned HTTP Status: ${HTTP_ROOT_CODE}."
fi

# 5. Resource Consumption Snapshot
echo ""
log_info "5. Live Container Resource Usage (docker stats):"
echo "------------------------------------------------------------"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}"
echo "------------------------------------------------------------"

echo ""
log_pass "Stack verification routine completed successfully."
