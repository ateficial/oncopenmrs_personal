# OncMRS: OpenMRS GCP Pilot for Oncology Department

[![OpenMRS](https://img.shields.io/badge/OpenMRS-Reference%20Application-blue.svg)](https://openmrs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-13%2B-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose%20v2-2496ED.svg)](https://www.docker.com/)
[![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000.svg)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/License-MPL%202.0-green.svg)](https://opensource.org/licenses/MPL-2.0)

This repository contains the infrastructure-as-code (IaC), container architecture, security policies, automation playbooks, and disaster recovery scripts for deploying **OpenMRS** on Google Cloud Platform (GCP) and on-premise hardware for an Oncology Department pilot.

---

## 🏛️ System Architecture

```
                                  INTERNET
                                     │
                             [ Port 80 / 443 ]
                                     ▼
                      ┌─────────────────────────────┐
                      │    NGINX (Reverse Proxy)    │
                      │  Let's Encrypt SSL & HSTS   │
                      └──────────────┬──────────────┘
                                     │ (Internal HTTP proxy_pass)
                  ┌──────────────────┴──────────────────┐
                  │   Docker Network: openmrs-internal  │
                  │                                     │
                  │   ┌─────────────────────────────┐   │
                  │   │   OpenMRS Reference App     │   │
                  │   │   (Tomcat - Port 8080)      │   │
                  │   └──────────────┬──────────────┘   │
                  │                  │ (JDBC 5432)      │
                  │   ┌──────────────┴──────────────┐   │
                  │   │   PostgreSQL / MariaDB      │   │
                  │   │   (Tuned for Health Records)│   │
                  │   └──────────────┬──────────────┘   │
                  └──────────────────┼──────────────────┘
                                     ▼
                   [ Named Volume: openmrs-db-data ]
                                     │
                          (pg_dump / mysqldump)
                                     ▼
                    [ Encrypted Cloud Backup to GCS ]
```

### Key Security & Architecture Highlights
1. **Network Isolation**: Database (`5432`/`3306`) and OpenMRS Tomcat (`8080`) are **not** bound to any host ports. Only NGINX exposes `80` (HTTP) and `443` (HTTPS).
2. **Data Persistence**: State is stored in Docker named volumes (`openmrs-db-data` and `openmrs-app-data`).
3. **Secret Isolation**: Passwords and keys reside in `.env` (gitignored). No credentials are committed to version control. Rotated secrets are stored locally in `rotated_secrets/` (gitignored).
4. **Automated Backups**: Custom compressed dumps with 7-day rolling local retention and encrypted uploads to Google Cloud Storage.
5. **Modular Ansible Orchestration**: Extended modular role structure (`common`, `kernel_tuning`, `docker`, `swap`, `backup`, `secret_rotation`) for automated host provisioning, log rotation, and credential management.

---

## 📁 Repository Structure

```
.
├── .env.example                         # Environment variables template
├── .gitignore                            # Secret, dump, and build artifact exclusions
├── README.md                             # Main project documentation
├── docker/
│   ├── docker-compose.yml                # Core multi-container definition
│   └── openmrs-runtime.properties.template # OpenMRS database configuration template
├── nginx/
│   ├── nginx.conf                        # NGINX master configuration
│   └── conf.d/
│       └── openmrs.conf                  # OpenMRS SSL reverse proxy site definition
├── ansible/
│   ├── ansible.cfg                       # Global Ansible execution settings
│   ├── site.yml                          # Master orchestrator playbook
│   ├── inventory/
│   │   ├── gcp_hosts.ini                 # Inventory for GCP Cloud Pilot instances
│   │   └── onprem_hosts.ini              # Inventory for local hospital hardware
│   ├── group_vars/
│   │   └── emr_servers.yml               # Shared host, kernel, and backup variables
│   └── roles/
│       ├── common/tasks/main.yml         # Base OS updates, utilities, timezone
│       ├── kernel_tuning/tasks/main.yml  # High-throughput sysctl optimizations
│       ├── docker/tasks/main.yml         # Docker CE & daemon log rotation limits
│       ├── swap/tasks/main.yml           # 4GB swapfile creation & boot persistence
│       ├── backup/tasks/main.yml         # Automated DB backup script & daily cron
│       └── secret_rotation/tasks/main.yml# Dynamic credential rotation routine
├── scripts/
│   ├── provision-gcp.sh                  # Task 1.1: GCP e2-standard-4 VM creation
│   ├── configure-firewall.sh             # Task 1.2: GCP VPC firewall & network hardening
│   ├── generate-secrets.sh               # Task 1.4: Cryptographic password generator (.env)
│   ├── setup-ssl.sh                      # Task 1.5: Automated Let's Encrypt TLS setup
│   ├── verify-stack.sh                   # Task 1.6: Stack healthcheck & resource metrics
│   ├── backup-db.sh                      # Task 0.4: Postgres backup & GCS upload
│   └── restore-db.sh                     # Task 0.4: Disaster recovery & restore script
└── docs/
    └── test-plan.md                      # 50 Synthetic patient records & clinical test suite
```

---

## 🚀 Quickstart Guide

### 1. Prerequisites
- Docker Engine $\ge$ 24.0 & Docker Compose $\ge$ v2.20
- Ansible $\ge$ 2.15 (for host provisioning and secret rotation)
- OpenSSL & Bash

### 2. Generate Secrets and Configure Environment
Run the secret generation script to produce a cryptographically secure `.env` file from the template:
```bash
chmod +x scripts/*.sh
./scripts/generate-secrets.sh
```

Inspect and update `.env` if you need custom domain names or bucket configurations:
```bash
cat .env
```

### 3. Start the Application Stack
```bash
docker compose -f docker/docker-compose.yml --env-file .env up -d
```

Monitor container initialization:
```bash
docker compose -f docker/docker-compose.yml logs -f
```

OpenMRS will be available via the NGINX reverse proxy on `http://localhost` (or configured `SERVER_NAME`).

### 4. Running Database Backups
To trigger a manual database backup, encryption, and off-site cloud upload:
```bash
./scripts/backup-db.sh
```

To restore from a backup:
```bash
./scripts/restore-db.sh /var/backups/openmrs/openmrs_db_YYYYMMDD_HHMM.dump
```

---

## 🔧 Ansible Provisioning & Secret Rotation

```bash
# 1. Test SSH connectivity to target host
cd ansible
ansible emr_servers -m ping

# 2. Dry-run execution to review pending changes
ansible-playbook site.yml --check --diff

# 3. Provision infrastructure, kernel rules, Docker, swap, and backup cron jobs
ansible-playbook site.yml

# 4. Execute on-demand dynamic database secret rotation
ansible-playbook site.yml --tags "secret_rotation"
```

---

## 🔒 Security & Contribution Rules

* **Branching Strategy**:
  - `main`: Protected production branch. Direct pushes are disabled; changes require a Pull Request.
  - `develop`: Primary integration branch for ongoing features and tasks.
* **Secrets Policy**: Never paste passwords, API tokens, `.env` content, or rotated secret files into issues, PRs, or public channels.
* **Patient Data Policy**: Only fictional, synthetic patient profiles (as documented in `docs/test-plan.md`) may be loaded into pilot environments. Real Protected Health Information (PHI) is strictly prohibited.

---

## 📄 License
Licensed under the [Mozilla Public License 2.0 (MPL 2.0)](https://opensource.org/licenses/MPL-2.0).
