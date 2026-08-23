#!/usr/bin/env bash
# ==============================================================================
# OpenMRS GCP Pilot — Task 1.5: Automated Let's Encrypt SSL & HTTPS Setup
# ==============================================================================
# Usage:
#   ./scripts/setup-ssl.sh oncology.yourdomain.com admin@yourdomain.com
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Load environment
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
fi

DOMAIN="${1:-${SERVER_NAME:-}}"
EMAIL="${2:-${ADMIN_EMAIL:-}}"

log_info() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [INFO] $1"
}

log_error() {
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] [ERROR] $1" >&2
}

if [[ -z "${DOMAIN}" || "${DOMAIN}" == "localhost" ]]; then
    log_error "A valid fully-qualified domain name (FQDN) is required for Let's Encrypt."
    echo "Usage: $0 <your-domain.com> <your-email@example.com>"
    exit 1
fi

if [[ -z "${EMAIL}" || "${EMAIL}" == "admin@example.com" ]]; then
    log_error "A valid admin contact email is required for Let's Encrypt."
    echo "Usage: $0 <your-domain.com> <your-email@example.com>"
    exit 1
fi

log_info "Initiating Let's Encrypt certificate generation for domain: ${DOMAIN} (${EMAIL})"

# 1. Request Certificate via Certbot Webroot
log_info "Running Certbot HTTP-01 webroot challenge..."
docker compose -f "${PROJECT_ROOT}/docker/docker-compose.yml" run --rm openmrs-certbot certonly \
    --webroot \
    -w /var/www/certbot \
    -d "${DOMAIN}" \
    --email "${EMAIL}" \
    --rsa-key-size 4096 \
    --agree-tos \
    --no-eff-email \
    --force-renewal

# 2. Update NGINX configuration paths
log_info "Updating NGINX configuration for ${DOMAIN}..."
NGINX_CONF="${PROJECT_ROOT}/nginx/conf.d/openmrs.conf"

sed -i.bak \
    -e "s|server_name localhost _|server_name ${DOMAIN}|g" \
    -e "s|/etc/letsencrypt/live/openmrs/|/etc/letsencrypt/live/${DOMAIN}/|g" \
    "${NGINX_CONF}"

# Enable 301 HTTPS Redirect
sed -i.bak \
    -e "s|# location / {|location / {|g" \
    -e "s|#     return 301 https://\$host\$request_uri;|    return 301 https://\$host\$request_uri;|g" \
    -e "s|# }|}|g" \
    "${NGINX_CONF}"

rm -f "${NGINX_CONF}.bak"

# 3. Reload NGINX to apply SSL certificate
log_info "Reloading NGINX reverse proxy..."
docker compose -f "${PROJECT_ROOT}/docker/docker-compose.yml" exec openmrs-nginx nginx -s reload

log_info "SSL configuration completed successfully!"
log_info "OpenMRS is now secured at: https://${DOMAIN}"
