# OncMRS: OpenMRS GCP Pilot for Oncology Department

[![OpenMRS](https://img.shields.io/badge/OpenMRS-Reference%20Application-blue.svg)](https://openmrs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-13%2B-blue.svg)](https://www.postgresql.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose%20v2-2496ED.svg)](https://www.docker.com/)
[![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000.svg)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/License-MPL%202.0-green.svg)](https://opensource.org/licenses/MPL-2.0)

This repository contains the infrastructure-as-code (IaC), container architecture, security policies, automation playbooks, and disaster recovery scripts for deploying **OpenMRS** on Google Cloud Platform (GCP) for an Oncology Department pilot.

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
                  │   │   PostgreSQL 13+            │   │
                  │   │   (Tuned for Health Records)│   │
                  │   └──────────────┬──────────────┘   │
                  └──────────────────┼──────────────────┘
                                     ▼
                   [ Named Volume: openmrs-db-data ]
                                     │
                          (pg_dump custom -Fc)
                                     ▼
                    [ Encrypted Cloud Backup to GCS ]
```

### Key Security & Architecture Highlights
1. **Network Isolation**: PostgreSQL (`5432`) and OpenMRS Tomcat (`8080`) are **not** bound to any host ports. Only NGINX exposes `80` (HTTP) and `443` (HTTPS).
2. **Data Persistence**: State is stored in Docker named volumes (`openmrs-db-data` and `openmrs-app-data`).
3. **Secret Isolation**: Passwords and keys reside in `.env` (gitignored). No credentials are committed to version control.
4. **Automated Backups**: Custom compressed dumps (`pg_dump -Fc`) with 7-day rolling local retention and AES-256 encrypted uploads to Google Cloud Storage.
5. **Idempotent Provisioning**: Ansible playbook (`ansible/site.yml`) bootstraps Ubuntu 22.04 LTS with Docker, UFW firewall, deploy user, 4GB swapfile, and kernel optimizations.

---

## 📁 Repository Structure

```
.
├── .env.example                      # Environment variables template
├── .gitignore                         # Secret, dump, and build artifact exclusions
├── README.md                          # Main project documentation
├── docker/
│   ├── docker-compose.yml             # Core multi-container definition
│   └── openmrs-runtime.properties.template # OpenMRS database configuration template
├── nginx/
│   ├── nginx.conf                     # NGINX master configuration
│   └── conf.d/
│       └── openmrs.conf               # OpenMRS SSL reverse proxy site definition
├── ansible/
│   ├── ansible.cfg                    # Ansible configuration defaults
│   ├── inventory.ini.example          # Sample production inventory file
│   └── site.yml                       # Ubuntu 22.04 VM bootstrap playbook
├── scripts/
│   ├── backup-db.sh                   # Automated Postgres backup & GCS upload
│   ├── restore-db.sh                  # Disaster recovery & database restore
│   └── generate-secrets.sh            # Secure password generator for .env
└── docs/
    └── test-plan.md                   # 50 Synthetic patient records & clinical test suite
```

---

## 🚀 Quickstart Guide

### 1. Prerequisites
- Docker Engine $\ge$ 24.0 & Docker Compose $\ge$ v2.20
- (Optional for Host Bootstrap) Ansible $\ge$ 2.14
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

## 🔒 Security & Contribution Rules

* **Branching Strategy**:
  - `main`: Protected production branch. Direct pushes are disabled; changes require a Pull Request.
  - `develop`: Primary integration branch for ongoing features and tasks.
* **Secrets Policy**: Never paste passwords, API tokens, or `.env` content into issues, PRs, or public channels.
* **Patient Data Policy**: Only fictional, synthetic patient profiles (as documented in `docs/test-plan.md`) may be loaded into pilot environments. Real Protected Health Information (PHI) is strictly prohibited.

---

## 📄 License
Licensed under the [Mozilla Public License 2.0 (MPL 2.0)](https://opensource.org/licenses/MPL-2.0).
