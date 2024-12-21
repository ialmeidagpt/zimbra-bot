#!/bin/bash
#===============================================================================
#
#          FILE: zimbra_bind_setup_and_prereqs.sh
#
#   DESCRIPTION: Instala dependências, configura Bind DNS, desativa IPv6 e instala Zimbra.
#
#===============================================================================

set -euo pipefail  # Exige que erros parem o script

HORAINICIAL=$(date +%T)

# Default values
DEFAULT_ZIMBRA_DOMAIN="zimbra.test"
DEFAULT_ZIMBRA_HOSTNAME="mail"
DEFAULT_ZIMBRA_SERVERIP="172.16.1.20"
DEFAULT_TIMEZONE="America/Sao_Paulo"
UBUNTU_VERSION="1"  # 1 para Ubuntu 18.04 ou 2 para Ubuntu 20.04
ADMIN_PASSWORD="MyAdminPassw0rd"

# Função de log
log() {
    echo -e "[INFO]: $1"
}

error_exit() {
    echo -e "[ERROR]: $1. Exiting."
    exit 1
}

# Step 1: Install Prerequisites
log "Installing system prerequisites..."
sudo apt update && sudo apt -y full-upgrade || error_exit "Failed to update and upgrade the system"
sudo apt install -y git net-tools netcat-openbsd libidn11 libpcre3 libgmp10 libexpat1 libstdc++6 libperl5* libaio1 resolvconf unzip pax sysstat sqlite3 bind9 bind9utils wget gnupg || error_exit "Failed to install required packages"

# Disable any running mail services
sudo systemctl disable --now postfix 2>/dev/null || true

# Step 2: Use predefined variables
log "Using default values for Zimbra configuration..."
ZIMBRA_DOMAIN=${DEFAULT_ZIMBRA_DOMAIN}
ZIMBRA_HOSTNAME=${DEFAULT_ZIMBRA_HOSTNAME}
ZIMBRA_SERVERIP=${DEFAULT_ZIMBRA_SERVERIP}
TimeZone=${DEFAULT_TIMEZONE}

log "Zimbra Base Domain: $ZIMBRA_DOMAIN"
log "Zimbra Mail Server Hostname: $ZIMBRA_HOSTNAME"
log "Zimbra Server IP Address: $ZIMBRA_SERVERIP"
log "Timezone: $TimeZone"

# Step 3: Configure /etc/hosts file
log "Configuring /etc/hosts..."
sudo cp /etc/hosts /etc/hosts.backup
sudo tee /etc/hosts > /dev/null <<EOF
127.0.0.1       localhost
$ZIMBRA_SERVERIP   $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN       $ZIMBRA_HOSTNAME
EOF

# Update system hostname
sudo hostnamectl set-hostname $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN || error_exit "Failed to set hostname"
log "Hostname updated to: $(hostname -f)"

# Configure timezone
sudo timedatectl set-timezone $TimeZone || error_exit "Failed to set timezone"
sudo apt remove -y ntp 2>/dev/null || true
sudo apt install -y chrony || error_exit "Failed to install chrony"
sudo systemctl restart chrony || error_exit "Failed to restart chrony"

# Step 4: Configure Bind DNS Server
log "Configuring Bind DNS server..."
sudo tee /etc/bind/named.conf.options > /dev/null <<EOF
options {
    directory "/var/cache/bind";
    forwarders {
        8.8.8.8;
        1.1.1.1;
    };
    dnssec-validation no;
    listen-on-v6 { any; };
};
EOF

sudo tee /etc/bind/named.conf.local > /dev/null <<EOF
zone "$ZIMBRA_DOMAIN" IN {
    type master;
    file "/etc/bind/db.$ZIMBRA_DOMAIN";
};
EOF

sudo tee /etc/bind/db.$ZIMBRA_DOMAIN > /dev/null <<EOF
\$TTL 1D
@       IN SOA  ns1.$ZIMBRA_DOMAIN. root.$ZIMBRA_DOMAIN. (
                                0       ; serial
                                1D      ; refresh
                                1H      ; retry
                                1W      ; expire
                                3H )    ; minimum
@               IN      NS      ns1.$ZIMBRA_DOMAIN.
@               IN      MX      0 $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN.
ns1             IN      A       $ZIMBRA_SERVERIP
$ZIMBRA_HOSTNAME IN      A       $ZIMBRA_SERVERIP
EOF

sudo systemctl enable bind9 || error_exit "Failed to enable Bind9"
sudo systemctl restart bind9 || error_exit "Failed to restart Bind9"

# Step 5: Disable IPv6
log "Disabling IPv6..."
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sudo sysctl -p || error_exit "Failed to persist IPv6 settings"


# Step 7: Download and Install Zimbra
log "Preparing to install Zimbra..."
ZIMBRA_URL="https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_3869.UBUNTU18_64.20190918004220.tgz"
wget $ZIMBRA_URL -O zimbra.tgz || error_exit "Failed to download Zimbra package"
tar xvf zimbra.tgz || error_exit "Failed to extract Zimbra package"
cd zcs*/ || error_exit "Failed to navigate to Zimbra directory"

log "Generating automatic answer file for installation..."
cat <<EOF > /tmp/zimbra-install-answers
Y
Y
Y
Y
Y
N
Y
Y
Y
Y
Y
Y
N
N
Y
EOF

log "Starting Zimbra installer..."
sudo ./install.sh 

log "Configuring Zimbra admin account..."
su - zimbra -c "zmprov sp admin@$DEFAULT_ZIMBRA_DOMAIN $ADMIN_PASSWORD" || error_exit "Failed to configure Zimbra admin account"

HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")

log "Installation completed in $TEMPO."
