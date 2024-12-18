#!/bin/bash

# Variáveis fornecidas como argumentos
SERVER_IP=$1    # Primeiro argumento: IP do servidor
HOSTNAME=$2     # Segundo argumento: Hostname do servidor
DOMAIN=$3       # Terceiro argumento: Nome do domínio
ZIMBRA_URL=$4   # Quarto argumento: URL do Zimbra

# Validação das variáveis obrigatórias
if [ -z "$SERVER_IP" ] || [ -z "$HOSTNAME" ] || [ -z "$DOMAIN" ] || [ -z "$ZIMBRA_URL" ]; then
    echo "Erro: Variáveis SERVER_IP, HOSTNAME, DOMAIN e ZIMBRA_URL são obrigatórias."
    echo "Uso: ./zimbra.sh <SERVER_IP> <HOSTNAME> <DOMAIN> <ZIMBRA_URL>"
    exit 1
fi

# Configuração inicial
HORAINICIAL=$(date +%T)
LOG="/var/log/zimbra.sh"

# Configura hostname e hosts
echo "$HOSTNAME" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1       localhost.localdomain localhost
127.0.1.1       $HOSTNAME.$DOMAIN $HOSTNAME
$SERVER_IP      $HOSTNAME.$DOMAIN $HOSTNAME
EOF

# Atualização do sistema
echo "Atualizando o sistema..."
apt update &>> $LOG
apt -y upgrade &>> $LOG
apt -y autoremove &>> $LOG

# Download e instalação do Zimbra
echo "Baixando o Zimbra Collaboration Community..."
wget $ZIMBRA_URL -O zimbra.tgz &>> $LOG
tar -xvf zimbra.tgz &>> $LOG

# Verificar se o arquivo zimbra.conf existe
if [ ! -f "/vagrant/zimbra.conf" ]; then
    echo "Erro: Arquivo zimbra.conf não encontrado em /vagrant!"
    exit 1
fi

echo "Iniciando a instalação do Zimbra com o arquivo zimbra.conf..."
cd zcs*/ || exit

# Carregar as variáveis do arquivo zimbra.conf
echo "Carregando variáveis do arquivo zimbra.conf..."
while IFS='=' read -r key value; do
    export "$key"="$value"
done < /vagrant/zimbra.conf

# Gerando respostas automáticas com base no log
echo "Gerando arquivo de respostas automáticas para instalação..."
cat <<EOF > /tmp/zimbra-install-answers
Y   # Aceitar os termos de licença
Y   # Usar o repositório do Zimbra
Y   # Instalar zimbra-ldap
Y   # Instalar zimbra-logger
Y   # Instalar zimbra-mta
N   # Não instalar zimbra-dnscache
Y   # Instalar zimbra-snmp
Y   # Instalar zimbra-store
Y   # Instalar zimbra-apache
Y   # Instalar zimbra-spell
Y   # Instalar zimbra-memcached
Y   # Instalar zimbra-proxy
Y   # Instalar zimbra-drive
N   # Não instalar zimbra-imapd
N   # Não instalar zimbra-chat
Y   # Continuar após as confirmações
EOF

# Remover comentários antes de passar para o instalador
sed -i 's/#.*//' /tmp/zimbra-install-answers

# Executar o Zimbra com instalação não interativa
echo "Iniciando a instalação do Zimbra..."
./install.sh < /tmp/zimbra-install-answers

# Verificar se a instalação foi concluída com sucesso
if [ $? -ne 0 ]; then
    echo "Erro: A instalação do Zimbra falhou. Verifique o log em $LOG."
    exit 1
fi

# Configuração final
echo "Zimbra instalado com sucesso. Acesse:"
echo "Admin Console: https://zimbra.$DOMAIN:7071"
echo "Webmail: https://zimbra.$DOMAIN"

HORAFINAL=$(date +%T)
TEMPO=$(date -u -d "0 $(( $(date -u -d "$HORAFINAL" +"%s") - $(date -u -d "$HORAINICIAL" +"%s") )) seconds" +"%H:%M:%S")
echo "Tempo de execução: $TEMPO"
exit 0
