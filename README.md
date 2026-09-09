# OncMRS: OpenMRS 3.x GCP Pilot for Oncology Department

[![OpenMRS 3.x](https://img.shields.io/badge/OpenMRS-3.x%20Microfrontends-blue.svg)](https://openmrs.org)
[![MariaDB](https://img.shields.io/badge/MariaDB-10.11%2B-blue.svg)](https://mariadb.org/)
[![Docker](https://img.shields.io/badge/Docker-Compose%20v2-2496ED.svg)](https://www.docker.com/)
[![Ansible](https://img.shields.io/badge/Ansible-Automation-EE0000.svg)](https://www.ansible.com/)
[![License](https://img.shields.io/badge/License-MPL%202.0-green.svg)](https://opensource.org/licenses/MPL-2.0)

This repository contains the infrastructure-as-code (IaC), container architecture, security policies, automation playbooks, and disaster recovery scripts for deploying **OpenMRS 3.x (O3 Microfrontend Architecture)** on Google Cloud Platform (GCP) and on-premise hardware for an Oncology Department pilot.

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
                                     │ 
                  ┌──────────────────┴──────────────────┐
                  │   Docker Network: openmrs-internal  │
                  │                                     │
                  │   ┌─────────────────────────────┐   │
                  │   │   OpenMRS 3.x Frontend SPA  │   │
                  │   │   (React / ESM / Carbon)    │   │
                  │   │   Location: /openmrs/spa/   │   │
                  │   └──────────────┬──────────────┘   │
                  │                  │ (REST & WS)      │
                  │   ┌──────────────┴──────────────┐   │
                  │   │   OpenMRS 3.x Backend API   │   │
                  │   │   (Spring / FHIR2 / Tomcat) │   │
                  │   │   Location: /openmrs/       │   │
                  │   └──────────────┬──────────────┘   │
                  │                  │ (JDBC 3306)      │
                  │   ┌──────────────┴──────────────┐   │
                  │   │   MariaDB 10.11 Database    │   │
                  │   │   (Tuned for Health Records)│   │
                  │   └──────────────┬──────────────┘   │
                  └──────────────────┼──────────────────┘
                                     ▼
                   [ Named Volume: openmrs-db-data ]
                                     │
                           (mariadb-dump / mysqldump)
                                     ▼
                    [ Encrypted Cloud Backup to GCS ]
```

### Key Security & Architecture Highlights
1. **Modern Microfrontends**: Built on OpenMRS 3.x (O3) with modular React single-page clinical workflows and patient dashboards.
2. **Network Isolation**: MariaDB (`3306`), Tomcat Backend (`8080`), and Frontend (`80`) are **not** exposed to the public host. Only NGINX exposes host ports `80` (HTTP) and `443` (HTTPS).
3. **Data Persistence**: State is stored in Docker named volumes (`openmrs-db-data` and `openmrs-app-data`).
4. **Secret Isolation**: Passwords and keys reside in `.env` (gitignored). Rotated credentials saved in `rotated_secrets/` (gitignored).
5. **Automated Backups**: Compressed database dumps with 7-day rolling local retention and encrypted uploads to Google Cloud Storage.
6. **Modular Ansible Orchestration**: Extended modular roles (`common`, `kernel_tuning`, `docker`, `swap`, `backup`, `secret_rotation`) for automated host provisioning and dynamic password rotation.

---

## 📁 Repository Structure

```
.
├── .env.example                         # Environment variables template
├── .gitignore                            # Secret, dump, and build artifact exclusions
├── README.md                             # Main project documentation
├── docker/
│   ├── docker-compose.yml                # OpenMRS 3.x multi-container definition
│   └── openmrs-runtime.properties.template # OpenMRS database configuration template
├── nginx/
│   ├── nginx.conf                        # NGINX master configuration
│   └── conf.d/
│       └── openmrs.conf                  # OpenMRS 3.x SPA & API reverse proxy definition
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
│   ├── backup-db.sh                      # Task 0.4: Database backup & GCS upload
│   └── restore-db.sh                     # Task 0.4: Disaster recovery & restore script
└── docs/
    └── test-plan.md                      # 50 Synthetic patient records & clinical test suite
```

---

## 🚀 One-Command Deployment Guide for Brand-New Linux VMs

You can fully provision, tune, secure, and deploy the entire OpenMRS 3.x stack onto a completely fresh, newly created Linux Virtual Machine (Ubuntu 22.04 / 24.04 LTS on GCP, AWS, Azure, DigitalOcean, or Bare Metal) using **only one command**:

### ⚡ The Command

SSH into your new virtual machine and paste this single command:

```bash
curl -fsSL https://raw.githubusercontent.com/ahmed-tagg/OncMRS/develop/bootstrap.sh | sudo bash
```

*(Alternative: If you have already cloned the repository onto the machine, you can simply run `sudo ./bootstrap.sh` from inside the project directory).*

---

### 📋 Prerequisites

* **Operating System**: Ubuntu 22.04 LTS or 24.04 LTS (Debian 11/12 also supported).
* **Hardware Sizing**: Minimum 8GB RAM (recommended: 16GB RAM / 4 vCPUs, e.g. GCP `e2-standard-4`).
* **Firewall Rules**: Allow inbound TCP on port `80` (HTTP) and port `443` (HTTPS).

---

### ⚙️ What the Script Automates (Zero Configuration Required)

When you execute this single command, the bootstrapper automatically executes the complete end-to-end rollout without asking for any manual inputs:

1. **Repository Bootstrapping**:
   - Detects if running on a fresh VM, installs `curl` and `git` automatically, and clones the latest `develop` branch directly into `/opt/oncopenmrs`.
2. **Toolchain Installation**:
   - Non-interactively installs `python3`, `openssl`, `ca-certificates`, `gnupg`, and `ansible`.
   - Installs official **Docker CE** and the Docker Compose plugin via Docker's official package repositories.
3. **Cryptographic Secret Generation**:
   - Detects if `.env` is absent and generates cryptographically secure, high-entropy 32-character passwords for MariaDB and database backup encryption without echoing them to logs.
4. **Automated Host & Kernel Optimizations (via Ansible)**:
   - Sets server timezone to `Africa/Cairo`.
   - Allocates and activates a persistent **4GB Swap Space** (`/swapfile`) with `/etc/fstab` boot persistence to prevent out-of-memory container terminations.
   - Tunes Linux kernel sysctl parameters for high clinical throughput (`vm.swappiness=10`, `net.core.somaxconn=1024`, `fs.file-max=2097152`).
   - Configures Docker daemon log rotation (`10m` size ceiling, max 3 files) to prevent disk exhaustion.
   - Installs automated database backup scripts and sets up a daily **02:00 AM** cron job.
5. **OpenMRS 3.x Microfrontend Stack Launch**:
   - Pulls all Docker images and starts the multi-container topology:
     - `openmrs-db` (MariaDB 10.11 with health checks)
     - `openmrs-backend` (Spring / FHIR2 Core API with automatic Liquibase table creation)
     - `openmrs-frontend` (OpenMRS 3.x Microfrontends SPA)
     - `openmrs-nginx` (Reverse proxy with `/openmrs/spa/` routing and TLS gateway)
     - `openmrs-certbot` (Automated Let's Encrypt renewal loop)
6. **Automated Verification & Diagnostics**:
   - Runs `verify-stack.sh` to validate container runtimes and MariaDB ping health.
   - Discovers the host's public IP and displays access links.

---

### 🏥 Accessing Your Deployed System

Once the bootstrapper completes, open your web browser:

* **Clinical Microfrontend (SPA)**: `http://<YOUR_VM_PUBLIC_IP>/openmrs/spa/home`
* **Legacy Admin Console**: `http://<YOUR_VM_PUBLIC_IP>/openmrs/`
* **Default Username**: `admin`
* **Default Password**: `Admin123` *(Be sure to change this upon initial login)*

> [!NOTE]
> **First-Time Boot Duration**: On the first start, OpenMRS creates ~240 database tables and executes over 1,000 Liquibase migrations. This initialization process typically takes **2 to 3 minutes**. If you see a loading screen or setup wizard initially, allow 2–3 minutes for Liquibase to finish.

---

### 🛠️ Common Operations & Management

All project files on the Linux VM are located at `/opt/oncopenmrs`:

```bash
# View backend database migration progress
docker compose -f /opt/oncopenmrs/docker/docker-compose.yml logs -f openmrs-backend

# View status of all running containers
docker compose -f /opt/oncopenmrs/docker/docker-compose.yml ps

# Trigger an immediate database backup manually
sudo /opt/oncopenmrs/scripts/backup-db.sh

# Restart the OpenMRS stack
docker compose -f /opt/oncopenmrs/docker/docker-compose.yml restart

# Stop the stack
docker compose -f /opt/oncopenmrs/docker/docker-compose.yml down
```

---

## 🌐 Remote Deployment from Workstation

To deploy to a remote target VM from your local machine with a single command:

```bash
./scripts/deploy-remote.sh <TARGET_VM_IP> [SSH_USER] [SSH_KEY]
```

---

## 🔧 Ansible Provisioning & Secret Rotation

If running Ansible directly on the target VM (defaults to `inventory/local.ini`):

```bash
cd ansible
ansible-playbook site.yml
```

To execute on-demand dynamic database secret rotation:
```bash
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
