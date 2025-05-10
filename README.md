# Post-Installation Setup for PostgreSQL

---

## Table of Contents

1. [Update postgreSQL Server Configuration](#1-update-postgresql-server-configuration)
2. [pgAdmin Configuration](#2-pgadmin-configuration)
3. [Configuring Backups](#3-configuring-backups)
4. [Creating Database Users and Roles](#4-creating-database-users-and-roles)
5. [Viewing Terraform State](#5-viewing-terraform-state)

---

## 1. Update postgreSQL Server Configuration

- Allow remote connections.

```bash
/etc/postgresql/*/main/postgresql.conf

listen_addresses = '0.0.0.0' # Add server address here is prefered

/etc/postgresql/*/main/pg_hba.conf

# IPv4 local connections: # Add server address(es) here is prefered
host    all             all             0.0.0.0/0          scram-sha-256

systemctl restart postgresql.service
```

- Set postgres user password.

```bash
sudo -u postgres psql

\password postgres # Set a strong postgres user password
```

## 2. pgAdmin Configuration

- Create the configuration database

```bash
/usr/pgadmin4/venv/bin/python /usr/pgadmin4/web/setup.py setup-db

chown --recursive www-data:www-data /var/lib/pgadmin4/

chmod --recursive 0770 /var/lib/pgadmin4/
```

- Add certificates

```bash
# These can be from your own CA, self signed or set up with ACME etc.
mkdir /etc/apache2/ssl

/etc/apache2/ssl/cert-name.pem

/etc/apache2/ssl/key-name.key

systemctl restart apache2.service
```

## 3. Configuring Backups

- Add any required additional users to postgres group

- Power down container

```bash
# In Proxmox
mkdir -p /mnt/nfs/backups/postgresql/<database name>

chmod 0770 /mnt/nfs/backups/postgresql/<database name>

# For an explanation of 100{uid}:100{gid} read up on Proxmox Bind Mounts if required
chown 100{uid}:100{gid} /mnt/nfs/backups/postgresql/<database name>

echo 'mp0: /mnt/nfs/backups/postgresql/<database>,mp=/mnt/backups/<database>' >> /etc/pve/lxc/<lxc id>.conf
```

- Power on container

- Create the backup service unit

```bash
/etc/systemd/system/<database name>-backup.service

[Unit]
Description=<Database name> backup

[Service]
SyslogIdentifier=<database>-backup
WorkingDirectory=/mnt/backups/<database>
User=postgres
Group=postgres
ExecStart=/usr/bin/pg_dump <database name> >> "<database>-dump-$(date +%Y%m%d).sql"
Type=oneshot
RemainAfterExit=yes

[Install]
# Started by <database name>-backup.timer
```

- Create the backup service timer.

```bash
/etc/systemd/system/<database name>-backup.timer

[Unit]
Description=Run <database name> backup daily at 2am

[Timer]
Unit=<database name>-backup.service
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target

systemctl daemon-reload

systemctl enable --now <database name>-backup.timer
```

- Create the backup cleanup service.

```bash
/etc/systemd/system/<database name>-backup-cleanup.service

[Unit]
Description=<Database name> backup cleanup service

[Service]
SyslogIdentifier=<database name>-backup-cleanup
WorkingDirectory=/mnt/backups/<database name>
User=postgres
Group=postgres
ExecStart=/usr/bin/find . -mindepth 1 -maxdepth 1 -type f -mtime +7 -exec rm -rf {} \;
Type=oneshot
RemainAfterExit=yes

[Install]
# Started by <database name>-backup-cleanup.timer
```

- Create the backup cleanup service timer.

```bash
/etc/systemd/system/<database name>-backup-cleanup.timer

[Unit]
Description=Run <database name> backup cleanup daily at 2:15am

[Timer]
Unit=<database name>-backup-cleanup.service
OnCalendar=*-*-* 02:15:00
Persistent=true

[Install]
WantedBy=timers.target

systemctl daemon-reload

systemctl enable --now <database name>-backup-cleanup.timer
```

## 4. Creating Database Users and Roles

- Switch to the PostgreSQL User

```bash
# If using CLI
sudo -u postgres psql
```

- Create a New User

```sql
CREATE USER <new_user> WITH PASSWORD <'user_password'>;
```

- Create a Database Owned by the New Role

```sql
CREATE DATABASE <new_database>;
```

- Grant Privileges

```sql
GRANT <REQUIRED PRIVILEGES> ON DATABASE <new_database> TO <new_user>;
```

- If public schema access is required to the new database

```sql
\c <new_database>

ALTER SCHEMA public OWNER TO <new_user>;
```

## 5. Viewing Terraform State

```sql
# Connect as terraform user (created via the above step)
psql -h <server IP/fqdn> -U terraform terraform_state

# View terraform state Schema
\dt terraform_remote_state.*

# View table structure
\d terraform_remote_state.states

# View state data

SET search_path TO terraform_remote_state;

SELECT * FROM states WHERE name = '<terraform workspace>';
```

## Requirements

| Name                                                                     | Version |
| ------------------------------------------------------------------------ | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | < 2.0.0 |
| <a name="requirement_proxmox"></a> [proxmox](#requirement_proxmox)       | < 1.0.0 |

## Providers

| Name                                                         | Version |
| ------------------------------------------------------------ | ------- |
| <a name="provider_proxmox"></a> [proxmox](#provider_proxmox) | 0.77.0  |

## Modules

No modules.

## Resources

| Name                                                                                                                                                                      | Type     |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [proxmox_virtual_environment_container.postgresql](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_container)               | resource |
| [proxmox_virtual_environment_file.postgresql](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_file)                         | resource |
| [proxmox_virtual_environment_firewall_options.postgresql](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_firewall_options) | resource |
| [proxmox_virtual_environment_firewall_rules.postgresql](https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_firewall_rules)     | resource |

## Inputs

| Name                                                                                    | Description                         | Type     | Default | Required |
| --------------------------------------------------------------------------------------- | ----------------------------------- | -------- | ------- | :------: |
| <a name="input_DEV_ROOT_PASSWORD"></a> [DEV_ROOT_PASSWORD](#input_DEV_ROOT_PASSWORD)    | Password for the root user          | `string` | `""`    |    no    |
| <a name="input_PROD_ROOT_PASSWORD"></a> [PROD_ROOT_PASSWORD](#input_PROD_ROOT_PASSWORD) | Password for the root user          | `string` | `""`    |    no    |
| <a name="input_PROXMOX_URL"></a> [PROXMOX_URL](#input_PROXMOX_URL)                      | The URL for the Proxmox environment | `string` | n/a     |   yes    |

## Outputs

No outputs.
