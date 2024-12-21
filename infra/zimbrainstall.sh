#!/bin/bash
#===============================================================================
#
#          FILE: zimbra_bind_setup_and_prereqs.sh
#
#         USAGE: ./zimbra_bind_setup_and_prereqs.sh
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
UBUNTU_VERSION="1"  # Defina 1 para Ubuntu 18.04 ou 2 para Ubuntu 20.04
ADMIN_PASSWORD="MyAdminPassw0rd"

# Step 1: Install Prerequisites
echo -e "\n[INFO]: Installing system prerequisites..."
sudo apt update && sudo apt -y full-upgrade
sudo apt install -y git net-tools netcat-openbsd libidn11 libpcre3 libgmp10 libexpat1 libstdc++6 libperl5* libaio1 resolvconf unzip pax sysstat sqlite3 bind9 bind9utils

# Disable any running mail services
sudo systemctl disable --now postfix 2>/dev/null || true

# Step 2: Use predefined variables
echo "Using default values for Zimbra configuration..."
ZIMBRA_DOMAIN=${DEFAULT_ZIMBRA_DOMAIN}
ZIMBRA_HOSTNAME=${DEFAULT_ZIMBRA_HOSTNAME}
ZIMBRA_SERVERIP=${DEFAULT_ZIMBRA_SERVERIP}
TimeZone=${DEFAULT_TIMEZONE}

echo "Zimbra Base Domain: $ZIMBRA_DOMAIN"
echo "Zimbra Mail Server Hostname: $ZIMBRA_HOSTNAME"
echo "Zimbra Server IP Address: $ZIMBRA_SERVERIP"
echo "Timezone: $TimeZone"
echo ""

# Step 3: Configure /etc/hosts file
echo -e "[INFO]: Configuring /etc/hosts..."
sudo cp /etc/hosts /etc/hosts.backup
sudo tee /etc/hosts<<EOF
127.0.0.1       localhost
$ZIMBRA_SERVERIP   $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN       $ZIMBRA_HOSTNAME
EOF

# Update system hostname
sudo hostnamectl set-hostname $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN
echo -e "[INFO]: Hostname updated to: $(hostname -f)\n"

# Configure timezone
sudo timedatectl set-timezone $TimeZone
sudo apt remove -y ntp 2>/dev/null || true
sudo apt install -y chrony
sudo systemctl restart chrony

# Step 4: Configure Bind DNS Server
echo -e "\n[INFO]: Configuring Bind DNS server..."
sudo cp /etc/resolvconf/resolv.conf.d/head /etc/resolvconf/resolv.conf.d/head.backup
sudo tee /etc/resolvconf/resolv.conf.d/head<<EOF
search $ZIMBRA_DOMAIN
nameserver 127.0.0.1
nameserver $ZIMBRA_SERVERIP
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved
sudo systemctl enable resolvconf
sudo systemctl restart resolvconf

sudo tee /etc/resolv.conf<<EOF
search $ZIMBRA_DOMAIN
nameserver 127.0.0.1
nameserver $ZIMBRA_SERVERIP
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF

# Configure Bind DNS zone
sudo cp /etc/bind/named.conf.local /etc/bind/named.conf.local.backup
sudo tee -a /etc/bind/named.conf.local<<EOF
zone "$ZIMBRA_DOMAIN" IN {
    type master;
    file "/etc/bind/db.$ZIMBRA_DOMAIN";
};
EOF

sudo tee /etc/bind/db.$ZIMBRA_DOMAIN<<EOF
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

sudo sed -i 's/dnssec-validation yes/dnssec-validation no/g' /etc/bind/named.conf.options

sudo tee /etc/bind/named.conf.options<<EOF
options {
    directory "/var/cache/bind";

    forwarders {
        8.8.8.8;
        1.1.1.1;
    };

    dnssec-validation auto;

    listen-on-v6 { any; };
};
EOF

sudo systemctl enable bind9
sudo systemctl restart bind9

# Step 5: Disable IPv6
echo -e "\n[INFO]: Disabling IPv6..."
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1
sudo tee -a /etc/sysctl.conf<<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

sudo sysctl -p

# Step 6: Validate DNS Configuration
echo -e "\n[INFO]: Validating DNS setup..."
dig A $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN @127.0.0.1 +short
dig MX $ZIMBRA_DOMAIN @127.0.0.1 +short

# Step 7: Download and Install Zimbra
echo -e "\n[INFO]: Preparing to install Zimbra..."

# Verificar conectividade com o repositório Zimbra
if [[ "$UBUNTU_VERSION" == "1" ]]; then
    ZIMBRA_URL="https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_3869.UBUNTU18_64.20190918004220.tgz"
elif [[ "$UBUNTU_VERSION" == "2" ]]; then
    ZIMBRA_URL="https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_4179.UBUNTU20_64.20211118033954.tgz"
else
    echo -e "\n[ERROR]: Invalid Ubuntu version specified. Exiting."
    exit 1
fi

cd ~/
wget $ZIMBRA_URL -O zimbra.tgz
tar xvf zimbra.tgz
cd zcs*/

# Iniciar o instalador do Zimbra
echo -e "\n[INFO]: Starting Zimbra installer..."
sudo ./install.sh

if [ $? -eq 0 ]; then
    su - zimbra -c "zmprov sp admin@$DEFAULT_ZIMBRA_DOMAIN $ADMIN_PASSWORD"
    echo -e "\n[INFO]: Installation and configuration completed successfully."
else
    echo -e "\n[ERROR]: Installation failed. Check logs in /tmp/zimbra-install.log."
    exit 1
fi

HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")

echo -e "\n[INFO]: Installation completed in $TEMPO."