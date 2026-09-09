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

## 🚀 Single-Command Quickstart (Brand-New VM)

On any newly provisioned virtual machine (Ubuntu 22.04 / 24.04 on GCP, AWS, Azure, or On-Premise), you can get the entire system configured, optimized, and running with **one single command**:

```bash
sudo ./bootstrap.sh
```

### What this single command does automatically:
1. **Installs Missing Tools**: Installs `curl`, `git`, `python3`, `python3-pip`, `ansible`, and `openssl` if not present.
2. **Generates Cryptographic Secrets**: Automatically creates `.env` with strong random passwords for MariaDB and backups.
3. **Applies Host Optimizations (Ansible)**:
   - Sets timezone to `Africa/Cairo` and upgrades base packages.
   - Configures kernel sysctl parameters (`vm.swappiness=10`, `somaxconn=1024`, `file-max=2097152`).
   - Allocates and activates 4GB swap space (`/swapfile`) with `/etc/fstab` boot persistence.
   - Installs Docker CE & Compose plugin with daemon log rotation (`10m` x 3).
   - Installs automated database backup script and configures a daily `02:00 AM` cron job.
4. **Deploys OpenMRS 3.x Containers**: Starts `openmrs-db`, `openmrs-backend`, `openmrs-frontend`, and `openmrs-nginx`.
5. **Verifies Health**: Runs end-to-end container and HTTP verification.

---

## 🪟 Windows Single-Command Quickstart

To run the full OpenMRS 3.x stack on your local Windows workstation (PowerShell, Command Prompt, or Git Bash), simply execute the startup script from the project root:

```powershell
# From PowerShell / Terminal
.\start.ps1

# Or from Command Prompt / Git Bash / Double-click
.\start.bat
```

### What this Windows command does automatically:
1. **Verifies Docker Installation**: Checks whether Docker is installed on your Windows machine and provides download instructions if missing.
2. **Starts Docker Engine**: Detects if the Docker daemon is stopped, automatically launches **Docker Desktop**, and waits until the Docker daemon is fully initialized and responsive.
3. **Prepares Environment**: Automatically initializes `.env` from `.env.example` if not already created and syncs it with `docker/.env`.
4. **Pulls Container Images**: Pulls the latest OpenMRS 3.x backend, frontend SPA, MariaDB, and NGINX images.
5. **Launches the Stack**: Starts all services in the background and reports container health.

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
