#!/bin/bash
set -e

# pct exec helper function
pct_exec() {
  pct exec "$1" -- bash -c "$2"
}

update() {
  pct_exec "$1" 'apt-get update'
  pct_exec "$1" 'DEBIAN_FRONTEND=noninteractive apt-get upgrade --yes --option Dpkg::Options::="--force-confold" --option Dpkg::Options::="--force-confdef"'
}

# Adds deployment specific rules, further to Golden Image
firewall_policy() {
  pct_exec "$1" 'iptables --append INPUT --protocol tcp --source x.x.x.x/x --dport 5432 --jump ACCEPT --match comment --comment "Allow postgreSQL"'
  pct_exec "$1" 'iptables --append INPUT --protocol tcp --source x.x.x.x/x --dport 443 --jump ACCEPT --match comment --comment "Allow pgAdmin"'
  pct_exec "$1" 'iptables --append INPUT --jump LOG --log-prefix "Policy Drop: " --log-level 4'
  pct_exec "$1" 'netfilter-persistent save'
}

ssh_keys() {
  pct_exec "$1" "ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key"
  pct_exec "$1" "ssh-keygen -t rsa -b 4096 N '' -f /etc/ssh/ssh_host_rsa_key"
}

postgresql_install() {
  pct_exec "$1" 'apt-get update'
  pct_exec "$1" 'DEBIAN_FRONTEND=noninteractive apt-get install --yes postgresql postgresql-contrib'
  pct_exec "$1" 'systemctl enable --now postgresql.service'

  sed_commands=(
    "s/^shared_buffers = 128MB/shared_buffers = 1GB/"
    "s/^#effective_cache_size = 4GB/effective_cache_size = 3GB/"
    "s/^#maintenance_work_mem = 64MB/maintenance_work_mem = 256MB/"
    "s/^#checkpoint_completion_target = 0.9/checkpoint_completion_target = 0.9/"
    "s/^#wal_buffers = -1/wal_buffers = 16MB/"
    "s/^#default_statistics_target = 100/default_statistics_target = 100/"
    "s/^#random_page_cost = 4.0/random_page_cost = 1.1/"
    "s/^#effective_io_concurrency = 1/effective_io_concurrency = 200/"
    "s/^#work_mem = 4MB/work_mem = 2621kB/"
    "s/^#huge_pages = try/huge_pages = off/"
    "s/^min_wal_size = 80MB/min_wal_size = 1GB/"
    "s/^max_wal_size = 1GB/max_wal_size = 4GB/"
    "s/^#logging_collector = off/logging_collector = on/"
    "s/^#log_destination = 'stderr'/log_destination = 'syslog'/"
    "s/^#syslog_facility = 'LOCAL0'/syslog_facility = 'LOCAL0'/"
    "s/^#syslog_ident = 'postgres'/syslog_ident = 'postgres'/"
  )

  for cmd in "${sed_commands[@]}"; do
    pct_exec "$1" "sed --in-place \"$cmd\" /etc/postgresql/*/main/postgresql.conf"
  done
}

pgadmin_install() {
  pct_exec "$1" 'curl --fail --silent --show-error --location https://www.pgadmin.org/static/packages_pgadmin_org.pub | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/packages-pgadmin-org.gpg --import'
  pct_exec "$1" 'chmod 0644 /usr/share/keyrings/packages-pgadmin-org.gpg'
  pct_exec "$1" "echo \"deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/\$(lsb_release --codename --short) pgadmin4 main\" > /etc/apt/sources.list.d/pgadmin4.list"
  pct_exec "$1" 'apt-get update'
  pct_exec "$1" 'apt-get install --yes pgadmin4 pgadmin4-web'
  pct_exec "$1" "cat << EOF > /usr/pgadmin4/web/config_local.py
LOG_FILE = '/var/log/pgadmin4/pgadmin4.log'
SQLITE_PATH = '/var/lib/pgadmin4/pgadmin4.db'
SESSION_DB_PATH = '/var/lib/pgadmin4/sessions'
STORAGE_DIR = '/var/lib/pgadmin4/storage'
AZURE_CREDENTIAL_CACHE_DIR = '/var/lib/pgadmin4/azurecredentialcache'
KERBEROS_CCACHE_DIR = '/var/lib/pgadmin4/kerberoscache'
EOF"

  pct_exec "$1" "cat << EOF > /etc/apache2/sites-available/pgadmin4.conf
<VirtualHost *:443>
    ServerAdmin <server admin email>
    ServerName <server fqdn>

    WSGIDaemonProcess pgadmin processes=1 threads=25 python-home=/usr/pgadmin4/venv
    WSGIScriptAlias / /usr/pgadmin4/web/pgAdmin4.wsgi

    <Directory /usr/pgadmin4/web>
        WSGIProcessGroup pgadmin
        WSGIApplicationGroup %{GLOBAL}
        Options FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog /var/log/apache2/pgadmin4-error_log
    CustomLog /var/log/apache2/pgadmin4-access_log combined

    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/cert-name.pem
    SSLCertificateKeyFile /etc/apache2/ssl/key-name.key
    SSLOptions +StrictRequire
    SSLProtocol -all +TLSv1.3
    SSLOpenSSLConfCmd       Curves X25519:prime256v1:secp384r1
    SSLHonorCipherOrder     off
    SSLSessionTickets       off
    Header always set Strict-Transport-Security 'max-age=63072000'
    Protocols h2 http/1.1
</VirtualHost>
EOF"

  pct_exec "$1" 'a2enmod ssl headers wsgi'
  pct_exec "$1" 'a2ensite pgadmin4.conf'
  pct_exec "$1" 'a2dissite 000-default.conf default-ssl.conf'
  pct_exec "$1" 'mkdir --parents /var/log/pgadmin4'
  pct_exec "$1" 'touch /var/log/pgadmin4/pgadmin4.log'
  pct_exec "$1" 'chown --recursive www-data:www-data /var/log/pgadmin4'
  pct_exec "$1" 'chmod --recursive 0755 /var/log/pgadmin4'
}

reboot() {
  sleep 30
  pct_exec "$1" 'systemctl reboot'
}

if [[ -f /root/installs/postgresql ]]; then
  echo 'LXC is already configured'
elif [[ "$2" == "post-start" ]]; then
  echo "Waiting for initial setup before commencing..."
  sleep 30
  update "$1"
  firewall_policy "$1"
  ssh_keys "$1"
  postgresql_install "$1"
  pgadmin_install "$1"
  reboot "$1"

  touch /root/installs/postgresql
  echo "Container $1 setup complete."
  lxc-info --name="$1"
fi
