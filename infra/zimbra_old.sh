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

set -o nounset  # Treat unset variables as an error

HORAINICIAL=$(date +%T)

# Step 1: Install Prerequisites
echo -e "\n[INFO]: Installing system prerequisites..."
sudo apt update && sudo apt -y full-upgrade
sudo apt install -y git net-tools netcat-openbsd libidn11 libpcre3 libgmp10 libexpat1 libstdc++6 libperl5* libaio1 resolvconf unzip pax sysstat sqlite3 bind9 bind9utils

# Disable any running mail services
sudo systemctl disable --now postfix 2>/dev/null

# Step 2: Input required variables
echo ""
read -p "Input Zimbra Base Domain (e.g., example.com): " ZIMBRA_DOMAIN
read -p "Input Zimbra Mail Server hostname (first part of FQDN, e.g., mail): " ZIMBRA_HOSTNAME
read -p "Input Zimbra Server IP Address: " ZIMBRA_SERVERIP
read -p "Input your timezone (e.g., America/Sao_Paulo): " TimeZone
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
sudo timedatectl set-ntp yes
sudo apt remove ntp -y 2>/dev/null
sudo apt install chrony -y
sudo systemctl restart chrony
sudo chronyc sources

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

sudo touch /etc/bind/db.$ZIMBRA_DOMAIN
sudo chgrp bind /etc/bind/db.$ZIMBRA_DOMAIN

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

# Restart Bind service
sudo systemctl enable bind9
sudo systemctl restart bind9

# Step 5: Disable IPv6
echo -e "\n[INFO]: Disabling IPv6..."

# Temporarily disable IPv6
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1

# Persist the configuration across reboots
sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup
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
echo "Select your Ubuntu version:"
echo "1) Ubuntu 18.04"
echo "2) Ubuntu 20.04"
read -p "Enter your choice (1 or 2): " ubuntu_version

if [[ "$ubuntu_version" == "1" ]]; then
    echo -e "\n[INFO]: Downloading Zimbra for Ubuntu 18.04..."
    cd ~/
    wget https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_3869.UBUNTU18_64.20190918004220.tgz
elif [[ "$ubuntu_version" == "2" ]]; then
    echo -e "\n[INFO]: Downloading Zimbra for Ubuntu 20.04..."
    cd ~/
    wget https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_4179.UBUNTU20_64.20211118033954.tgz
else
    echo -e "\n[ERROR]: Invalid choice. Exiting."
    exit 1
fi

# Extract and Install Zimbra
echo -e "\n[INFO]: Extracting Zimbra package..."
tar xvf zcs-8.8.15_GA_*.tgz
cd zcs*/

# Generate automatic answers
echo "Generating automatic answer file for installation..."
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

# Run Zimbra installer with automatic answers
echo "Starting Zimbra installation..."
./install.sh < /tmp/zimbra-install-answers

if [ $? -ne 0 ]; then
    echo "Error: Zimbra installation failed. Check the logs."
    exit 1
fi

HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")

echo "Zimbra installation completed successfully!"
echo "Admin Console: https://$ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN:7071"
echo "Webmail: https://$ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN"
echo "Installation duration: $TEMPO"
