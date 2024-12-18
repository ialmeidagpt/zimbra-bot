#!/bin/bash

# Variáveis fornecidas como argumentos
HOSTNAME=$1    # Primeiro argumento: Hostname do servidor
DOMAIN=$2      # Segundo argumento: Nome do domínio
INTERFACE=$3   # Interface do VirtualBox

# Validação das variáveis obrigatórias
if [ -z "$HOSTNAME" ] || [ -z "$DOMAIN" ] || [ -z "$INTERFACE" ]; then
    echo "Erro: Variáveis HOSTNAME, DOMAIN e INTERFACE são obrigatórias."
    echo "Uso: ./bind.sh <HOSTNAME> <DOMAIN> <INTERFACE>"
    exit 1
fi

# Configurações iniciais
HORAINICIAL=$(date +%T)
LOG="/var/log/bind9_setup.log"
SERVER_IP=$(ip addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

# Validar se o IP foi detectado corretamente
if [ -z "$SERVER_IP" ]; then
    echo "Erro: Não foi possível obter o IP da interface $INTERFACE."
    exit 1
fi

echo "IP detectado: $SERVER_IP"

IP_REVERSE=$(echo $SERVER_IP | awk -F. '{print $3 "." $2 "." $1}')
DOMAINREV="$IP_REVERSE.in-addr.arpa"

export DEBIAN_FRONTEND="noninteractive"

echo "Configuração do Bind9 DNS Server"
sleep 1

# Verificar permissões de root
if [ "$(id -u)" != "0" ]; then
    echo "Erro: Este script deve ser executado como root."
    exit 1
fi

# Atualização de pacotes e instalação do Bind9
echo "Atualizando pacotes e instalando Bind9..."
apt update &>> $LOG
apt -y upgrade &>> $LOG
apt -y install bind9 bind9utils bind9-doc dnsutils net-tools &>> $LOG

# Configuração do hostname e /etc/hosts
echo "Configurando hostname e /etc/hosts..."
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1       localhost.localdomain localhost
127.0.1.1       $HOSTNAME.$DOMAIN $HOSTNAME
$SERVER_IP      $HOSTNAME.$DOMAIN $HOSTNAME
EOF

# Configuração do Netplan para IP dinâmico
echo "Configurando Netplan para IP dinâmico..."
cat <<EOF > /etc/netplan/01-netcfg.yaml
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: true
EOF
netplan apply &>> $LOG

# Configuração do Bind9
echo "Configurando arquivos do Bind9..."
mkdir -p /var/lib/bind
chown root:bind /var/lib/bind
mkdir -p /var/log/named/
chown -R root:bind /var/log/named/

# named.conf
cat <<EOF > /etc/bind/named.conf
include "/etc/bind/named.conf.options";
include "/etc/bind/named.conf.local";
include "/etc/bind/named.conf.default-zones";
EOF

# named.conf.local
cat <<EOF > /etc/bind/named.conf.local
zone "$DOMAIN" IN {
    type master;
    file "/var/lib/bind/$DOMAIN.hosts";
    allow-query { any; };
    notify yes;
};

zone "$DOMAINREV" IN {
    type master;
    file "/var/lib/bind/$DOMAINREV.rev";
    allow-query { any; };
    notify yes;
};
EOF

# named.conf.options
cat <<EOF > /etc/bind/named.conf.options
options {
    directory "/var/cache/bind";
    statistics-file "/var/log/named/named.stats";
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    listen-on port 53 { 127.0.0.1; $SERVER_IP; };
    listen-on-v6 { any; };
    auth-nxdomain no;
    recursion yes;
    allow-query { any; };
    allow-recursion { any; };
};
logging {
    channel named_log {
        syslog local3;
        severity info;
    };
    category default { named_log; };
};
EOF

# Arquivo de zona direta
cat <<EOF > /var/lib/bind/$DOMAIN.hosts
\$ORIGIN $DOMAIN.
\$TTL 3600
@       IN      SOA     $HOSTNAME.$DOMAIN. root.$DOMAIN. (
                $(date +%Y%m%d%H) ; Serial dinâmico
                604800  ; Refresh
                86400   ; Retry
                2419200 ; Expire
                604800  ; Negative Cache TTL
);
@       IN      NS      $HOSTNAME.$DOMAIN.
@       IN      MX 10   mail.$DOMAIN.
@       IN      A       $SERVER_IP
$HOSTNAME   IN      A       $SERVER_IP
mail        IN      A       $SERVER_IP
www         IN      A       $SERVER_IP
EOF

# Arquivo de zona reversa
cat <<EOF > /var/lib/bind/$DOMAINREV.rev
\$ORIGIN $DOMAINREV.
\$TTL 3600
@       IN      SOA     $HOSTNAME.$DOMAIN. root.$DOMAIN. (
                $(date +%Y%m%d%H) ; Serial dinâmico
                604800  ; Refresh
                86400   ; Retry
                2419200 ; Expire
                604800  ; Negative Cache TTL
);
@       IN      NS      $HOSTNAME.$DOMAIN.
$(echo $SERVER_IP | awk -F. '{print $4}') IN PTR mail.$DOMAIN.
EOF

# Verificar configuração do Bind9 e reiniciar
echo "Verificando configurações do Bind9..."
named-checkconf &>> $LOG
named-checkzone $DOMAIN /var/lib/bind/$DOMAIN.hosts &>> $LOG
named-checkzone $DOMAINREV /var/lib/bind/$DOMAINREV.rev &>> $LOG
systemctl restart bind9

# Verificar serviço
if ! systemctl is-active --quiet bind9; then
    echo "Erro: O serviço Bind9 não foi iniciado corretamente."
    exit 1
fi

# Finalização
HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")

echo "Configuração concluída com sucesso!"
echo "Tempo de execução: $TEMPO"
exit 0
