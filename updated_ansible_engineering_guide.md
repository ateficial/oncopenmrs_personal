# Updated Ansible Playbook Engineering Specification
## OpenMRS 3.x Host Provisioning, Kernel Tuning, Database Backup Automation & Secret Rotation

| Parameter | Specification |
| :--- | :--- |
| **Automation Engine** | Ansible 2.15+ (Agentless) |
| **Target Infrastructure** | Ubuntu 22.04 LTS (GCP / On-Prem) |
| **Design Pattern** | Extended Modular Roles |
| **Scope Expansion** | OS + Backups + Rotation |

---

### Updated Specification Scope
This document expands the core OpenMRS Ansible automation architecture. In addition to base OS provisioning, high-throughput kernel tuning, swap allocation, and Docker engine setup, this updated guide includes fully automated MariaDB database backups (via cron) and dynamic database credential rotation routines.

---

## 1. Expanded Central Repository Structure (`/ansible`)

The expanded project layout introduces two new specialized roles under `roles/`:
* `backup`: for daily automated database dumping and retention management.
* `secret_rotation`: for on-demand credential rotation across MySQL and application containers.

### Complete Directory Tree Layout:

```text
openmrs-pilot/
└── ansible/
    ├── ansible.cfg                  # Global Ansible execution settings
    ├── inventory/
    │   ├── gcp_hosts.ini            # Inventory for GCP Cloud Pilot instances
    │   └── onprem_hosts.ini         # Inventory for target hospital local hardware
    ├── group_vars/
    │   └── emr_servers.yml          # Shared variables (swap size, kernel limits, backup parameters)
    ├── roles/
    │   ├── common/
    │   │   └── tasks/
    │   │       └── main.yml         # System updates, timezone, basic utilities
    │   ├── kernel_tuning/
    │   │   └── tasks/
    │   │       └── main.yml         # sysctl optimizations for 12-doctor concurrent load
    │   ├── docker/
    │   │   └── tasks/
    │   │       └── main.yml         # Official Docker CE setup & log rotation config
    │   ├── swap/
    │   │   └── tasks/
    │   │       └── main.yml         # Automatic swapfile creation against JVM OOM
    │   ├── backup/
    │   │   └── tasks/
    │   │       └── main.yml         # [NEW] Automated MariaDB dumps & cron retention
    │   └── secret_rotation/
    │       └── tasks/
    │           └── main.yml         # [NEW] Dynamic DB password rotation & service restart
    └── site.yml                     # Master orchestrator playbook
```

---

## 2. Environment Configurations & Global Variables

### `ansible/ansible.cfg`
```ini
[defaults]
inventory           = inventory/gcp_hosts.ini
remote_user         = ubuntu
private_key_file    = ~/.ssh/id_rsa
host_key_checking   = False
retry_files_enabled = False
stdout_callback     = yaml

[privilege_escalation]
become        = True
become_method = sudo
become_user   = root
```

### `ansible/inventory/gcp_hosts.ini`
```ini
[emr_servers]
emr-pilot-gcp ansible_host=34.123.45.6 ansible_user=ubuntu

[emr_servers:vars]
ansible_python_interpreter=/usr/bin/python3
```

### `ansible/group_vars/emr_servers.yml`
```yaml
# Host Performance & Kernel Parameters
swap_file_size_gb: 4
sysctl_swappiness: 10
sysctl_file_max: 2097152
sysctl_somaxconn: 1024
docker_log_max_size: "10m"
docker_log_max_file: "3"

# Backup & Secret Rotation Variables
db_user: "openmrs_user"
db_root_password: "InitialRootPasswordHere"  # Encrypt with ansible-vault in production
backup_retention_days: 7
```

---

## 3. Core Infrastructure & Host Provisioning Roles

### `roles/common/tasks/main.yml`
```yaml
- name: Update apt cache and upgrade all packages
  apt:
    update_cache: yes
    upgrade: dist

- name: Install baseline system utilities
  apt:
    name:
      - curl
      - wget
      - git
      - ufw
      - htop
      - iotop
      - ca-certificates
      - gnupg
      - lsb-release
    state: present

- name: Set system timezone to Africa/Cairo
  community.general.timezone:
    name: Africa/Cairo
```

### `roles/kernel_tuning/tasks/main.yml`
```yaml
- name: Optimize sysctl parameters for DB throughput and high socket queues
  sysctl:
    name: "{{ item.key }}"
    value: "{{ item.value }}"
    state: present
    reload: yes
  loop:
    - { key: 'vm.swappiness', value: "{{ sysctl_swappiness }}" }
    - { key: 'fs.file-max', value: "{{ sysctl_file_max }}" }
    - { key: 'net.core.somaxconn', value: "{{ sysctl_somaxconn }}" }
    - { key: 'net.ipv4.tcp_max_syn_backlog', value: '2048' }
```

### `roles/docker/tasks/main.yml`
```yaml
- name: Add Docker official GPG key
  apt_key:
    url: https://download.docker.com/linux/ubuntu/gpg
    state: present

- name: Add Docker repository
  apt_repository:
    repo: "deb [arch=amd64] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present

- name: Install Docker CE and Docker Compose Plugin
  apt:
    name:
      - docker-ce
      - docker-ce-cli
      - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin
    state: present
    update_cache: yes

- name: Configure Docker daemon log rotation limit
  copy:
    dest: /etc/docker/daemon.json
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "{{ docker_log_max_size }}",
          "max-file": "{{ docker_log_max_file }}"
        }
      }
    mode: '0644'

- name: Ensure Docker service is enabled and started
  systemd:
    name: docker
    state: started
    enabled: yes

- name: Add user to docker group
  user:
    name: "{{ ansible_user }}"
    groups: docker
    append: yes
```

### `roles/swap/tasks/main.yml`
```yaml
- name: Check if swap file exists
  stat:
    path: /swapfile
  register: swap_file_check

- name: Create 4GB swap file if non-existent
  command: "fallocate -l {{ swap_file_size_gb }}G /swapfile"
  when: not swap_file_check.stat.exists

- name: Set permissions and make swap
  file:
    path: /swapfile
    owner: root
    group: root
    mode: '0600'
  when: not swap_file_check.stat.exists

- name: Format swap space
  command: mkswap /swapfile
  when: not swap_file_check.stat.exists

- name: Enable swap space
  command: swapon /swapfile
  when: not swap_file_check.stat.exists

- name: Add swap to /etc/fstab for boot persistence
  mount:
    path: none
    src: /swapfile
    fstype: swap
    opts: sw
    state: present
```

---

## 4. Extended Automation Roles: Backups & Secret Rotation

### `roles/backup/tasks/main.yml` (Automated Database Backup)
```yaml
- name: Create host backup directory
  file:
    path: /var/backups/openmrs
    state: directory
    owner: root
    group: root
    mode: '0700'

- name: Deploy automated mysqldump & retention script
  copy:
    dest: /usr/local/bin/backup_openmrs_db.sh
    mode: '0700'
    content: |
      #!/bin/bash
      TIMESTAMP=$(date +%Y%m%d_%H%M%S)
      BACKUP_DIR="/var/backups/openmrs"
      CONTAINER_NAME="openmrs-mariadb"

      # Execute mysqldump inside container
      docker exec ${CONTAINER_NAME} mysqldump -u root -p"{{ db_root_password }}" --all-databases | gzip > "${BACKUP_DIR}/openmrs_db_${TIMESTAMP}.sql.gz"

      # Prune local backups older than configured retention days
      find ${BACKUP_DIR} -type f -name "*.sql.gz" -mtime +{{ backup_retention_days }} -delete

- name: Provision daily cron job for OpenMRS DB backup at 02:00 AM
  ansible.builtin.cron:
    name: "OpenMRS Daily Database Backup"
    minute: "0"
    hour: "2"
    job: "/usr/local/bin/backup_openmrs_db.sh > /var/log/openmrs_backup.log 2>&1"
```

### `roles/secret_rotation/tasks/main.yml` (On-Demand Credential Rotation)
```yaml
- name: Generate strong random database password
  set_fact:
    new_db_password: "{{ lookup('ansible.builtin.password', '/dev/null length=32 chars=ascii_letters,digits') }}"

- name: Update password inside active MariaDB container
  command: >
    docker exec openmrs-mariadb mysql -u root -p"{{ db_root_password }}" -e
    "ALTER USER '{{ db_user }}'@'%' IDENTIFIED BY '{{ new_db_password }}'; FLUSH PRIVILEGES;"

- name: Update DB password in OpenMRS application environment file
  lineinfile:
    path: /opt/openmrs/.env
    regexp: '^DB_PASSWORD='
    line: "DB_PASSWORD={{ new_db_password }}"

- name: Restart OpenMRS container to register new credentials
  community.docker.docker_container:
    name: openmrs-core
    state: restarted

- name: Store rotated credentials locally on control machine
  local_action:
    module: copy
    content: "Rotated DB Password on {{ ansible_date_time.iso8601 }}: {{ new_db_password }}
"
    dest: "./rotated_secrets/{{ inventory_hostname }}_db_secret.txt"
  no_log: true
```

---

## 5. Master Orchestrator & Deployment Workflow

### Master Playbook: `site.yml`
```yaml
- name: Bootstrap and Provision OpenMRS Host Infrastructure
  hosts: emr_servers
  become: yes
  roles:
    - common
    - kernel_tuning
    - docker
    - swap
    - backup
    # - secret_rotation  # Uncomment or pass via --tags for manual credential rotation
```

### Execution Step-by-Step Commands:
```bash
# 1. Initialize full expanded directory tree
mkdir -p ansible/inventory ansible/group_vars ansible/roles/{common,kernel_tuning,docker,swap,backup,secret_rotation}/tasks

# 2. Test SSH connectivity to target host
cd ansible
ansible emr_servers -m ping

# 3. Dry-run execution to review pending system updates
ansible-playbook site.yml --check --diff

# 4. Provision complete infrastructure, kernel rules, and backup cron jobs
ansible-playbook site.yml

# 5. Execute secret rotation routine on-demand
ansible-playbook site.yml --tags "secret_rotation"
```
