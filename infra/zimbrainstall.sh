#!/bin/bash
#===============================================================================
#
#          FILE: zimbra_bind_setup_and_prereqs.sh
#
#   DESCRIPTION: Instala dependências, configura Bind DNS, desativa IPv6 e instala Zimbra.
#
#===============================================================================

set -euo pipefail

HORAINICIAL=$(date +%T)

# Variável para a versão do Ubuntu
UBUNTU_VERSION="18" # Altere para "18" ou "20" conforme necessário.

# Valores padrão
DEFAULT_ZIMBRA_DOMAIN="zimbra.test"
DEFAULT_ZIMBRA_HOSTNAME="mail"
DEFAULT_ZIMBRA_SERVERIP="172.16.1.20"
DEFAULT_TIMEZONE="America/Sao_Paulo"
ADMIN_PASSWORD="MyAdminPassw0rd"

# Função de log
log() {
    echo -e "[INFO]: $1"
}

error_exit() {
    echo -e "[ERROR]: $1. Exiting."
    exit 1
}

# Step 1: Instalar dependências
log "Installing system prerequisites..."
sudo apt update && sudo apt -y full-upgrade || error_exit "Failed to update and upgrade the system"
sudo apt install -y git net-tools netcat-openbsd libidn11 libpcre3 libgmp10 libexpat1 libstdc++6 libperl5* libaio1 resolvconf unzip pax sysstat sqlite3 bind9 bind9utils wget gnupg || error_exit "Failed to install required packages"

# Disable any running mail services
sudo systemctl disable --now postfix 2>/dev/null || true

# Step 2: Configurar variáveis padrão
log "Using default values for Zimbra configuration..."
ZIMBRA_DOMAIN=${DEFAULT_ZIMBRA_DOMAIN}
ZIMBRA_HOSTNAME=${DEFAULT_ZIMBRA_HOSTNAME}
ZIMBRA_SERVERIP=${DEFAULT_ZIMBRA_SERVERIP}
TimeZone=${DEFAULT_TIMEZONE}

log "Zimbra Base Domain: $ZIMBRA_DOMAIN"
log "Zimbra Mail Server Hostname: $ZIMBRA_HOSTNAME"
log "Zimbra Server IP Address: $ZIMBRA_SERVERIP"
log "Timezone: $TimeZone"

# Step 3: Configurar /etc/hosts
log "Configuring /etc/hosts..."
sudo cp /etc/hosts /etc/hosts.backup
sudo tee /etc/hosts > /dev/null <<EOF
127.0.0.1       localhost
$ZIMBRA_SERVERIP   $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN       $ZIMBRA_HOSTNAME
EOF

sudo hostnamectl set-hostname $ZIMBRA_HOSTNAME.$ZIMBRA_DOMAIN || error_exit "Failed to set hostname"
log "Hostname updated to: $(hostname -f)"

sudo timedatectl set-timezone $TimeZone || error_exit "Failed to set timezone"
sudo apt remove -y ntp 2>/dev/null || true
sudo apt install -y chrony || error_exit "Failed to install chrony"
sudo systemctl restart chrony || error_exit "Failed to restart chrony"

# Step 4: Configurar chave GPG e repositório
log "Configuring Zimbra repository..."
if [ -f "/tmp/zimbra-pubkey.asc" ]; then
    sudo gpg --dearmor -o /usr/share/keyrings/zimbra.gpg /tmp/zimbra-pubkey.asc || error_exit "Failed to import Zimbra GPG key"
else
    error_exit "Zimbra GPG key file not found at /tmp/zimbra-pubkey.asc"
fi

echo "deb [signed-by=/usr/share/keyrings/zimbra.gpg arch=amd64] https://repo.zimbra.com/apt/87 bionic main" | sudo tee /etc/apt/sources.list.d/zimbra.list > /dev/null

sudo apt update || error_exit "Failed to update package list."

# Step 5: Instalar Zimbra
log "Preparing to install Zimbra..."
if [[ "$UBUNTU_VERSION" == "18" ]]; then
    ZIMBRA_URL="https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_3869.UBUNTU18_64.20190918004220.tgz"
elif [[ "$UBUNTU_VERSION" == "20" ]]; then
    ZIMBRA_URL="https://files.zimbra.com/downloads/8.8.15_GA/zcs-8.8.15_GA_4179.UBUNTU20_64.20211118033954.tgz"
else
    error_exit "Unsupported Ubuntu version. Please use '18' or '20'."
fi

if [ ! -f "zimbra.tgz" ]; then
    wget $ZIMBRA_URL -O zimbra.tgz || error_exit "Failed to download Zimbra package"
else
    log "Zimbra package already exists. Skipping download."
fi

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
sudo ./install.sh < /tmp/zimbra-install-answers || error_exit "Zimbra installation failed"

log "Configuring Zimbra admin account..."
su - zimbra -c "zmprov sp admin@$DEFAULT_ZIMBRA_DOMAIN $ADMIN_PASSWORD" || error_exit "Failed to configure Zimbra admin account"

HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")

log "Installation completed in $TEMPO."
