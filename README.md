# Projeto de Monitoramento e Ação em Fila de Emails

Este projeto tem como objetivo monitorar uma fila de emails em um servidor Zimbra, verificar se há remetentes suspeitos (por exemplo, endereços estrangeiros que enviam grande volume de mensagens) e, caso necessário, executar ações como bloqueio de contas, alteração de senha e registro de observações.

## Estrutura do Projeto

```
project/
├─ app.js                    # Ponto de entrada da aplicação
├─ controllers/
│  └─ mainController.js      # Controlador principal da aplicação
├─ services/
│  ├─ soapService.js         # Serviço de comunicação SOAP com o Zimbra
│  ├─ certService.js         # Serviço para checagem de certificados
│  ├─ fileService.js         # Serviço para operações de leitura/escrita no arquivo JSON
│  ├─ addressService.js      # Lógica de tratamento de endereços, IPs e bloqueio de contas
│  └─ ...                    # Outros serviços (se necessário)
└─ address_ip_data.json      # Arquivo JSON com o histórico de endereços e IPs
```

## Pré-requisitos

- Node.js instalado (versão LTS recomendada)
- Dependências do projeto instaladas

## Instalação

1. Clone o repositório:

   ```bash
   git clone https://github.com/usuario/projeto.git
   ```

2. Entre na pasta do projeto:

   ```bash
   cd projeto
   ```

3. Instale as dependências:
   ```bash
   npm install
   ```

## Variáveis de Ambiente

No arquivo `.env` você deverá definir as seguintes variáveis:

- `TOKEN_ID`: O token do seu bot do Telegram, utilizado para enviar notificações.
- `CHAT_ID`: O ID do chat (usuário/grupo) no Telegram para onde as notificações serão enviadas.
- `WSDL_ZIMBRA`: A URL WSDL do serviço SOAP do Zimbra (geralmente `https://IP:7071/service/admin/soap`).
- `USER_ADMIN_ZIMBRA`: O endereço de email de um usuário administrador no Zimbra, utilizado para autenticação e chamadas SOAP.
- `PASSWORD`: A senha do usuário administrador do Zimbra.
- `HOSTNAME`: O hostname do servidor Zimbra a ser monitorado (ex: `mail.dominio.com`).
- `SPAM_THRESHOLD`: Um número que indica o limite de mensagens enviadas por um remetente antes de ser considerado suspeito (ex: `60`).
- `SITES`: Uma lista de emails (separados por vírgula) que serão monitorados ou checados com mais atenção (ex: `email1@dominio.com,email2@dominio.com`).
- `TOKEN_IPINFO`: O token do serviço de geolocalização (IP Info) para identificar a origem do IP. Caso não seja necessário, pode permanecer vazio.
- `KNOWN_EMAIL_SERVICES`: Lista de domínios conhecidos de serviços de email (separados por vírgula) que não devem ser considerados suspeitos apenas pela origem.

**Exemplo de arquivo `.env`**:

````env
TOKEN_ID=256555:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
CHAT_ID=15854321
WSDL_ZIMBRA=https://192.168.0.10:7071/service/admin/soap
USER_ADMIN_ZIMBRA=admin@dominio.com
PASSWORD=senha_super_secreta
HOSTNAME=mail.dominio.com
SPAM_THRESHOLD=60
SITES=email1@dominio.com,email2@dominio.com
TOKEN_IPINFO=seu_token_de_ipinfo
KNOWN_EMAIL_SERVICES=google.com,outlook.com,microsoft.com,hotmail.com,yahoo.com,live.com

## Execução

Para executar o projeto:

```bash
node app.js
````

O script irá:

- Obter um token de autenticação via SOAP.
- Checar a fila de e-mails.
- Identificar remetentes suspeitos com base em volume e origem do IP.
- Executar ações (bloqueio, adição de observação, redefinição de senha) quando necessário.
- Logar as informações e enviar mensagens via Telegram (caso esteja configurado no `soapService`).

## Manutenção e Limpeza de Código

Este projeto foi refatorado para separar responsabilidades. Os principais pontos da refatoração incluem:

- `app.js`: Agora é o ponto de entrada, mantendo o código mais limpo.
- `mainController.js`: Centraliza a lógica do fluxo principal.
- `fileService.js`: Responsável pelo acesso ao arquivo JSON.
- `addressService.js`: Lida com a lógica de filtragem de IPs, identificação de serviços conhecidos, bloqueio e observações.
- `soapService.js` e `certService.js`: Mantêm a lógica específica de serviços externos.

Dessa forma, o código é mais fácil de manter, testar e evoluir.

## Contribuições

Sinta-se à vontade para abrir issues e enviar PRs com correções, melhorias e novas funcionalidades.

## Licença

Este projeto está sob a licença MIT. Veja o arquivo [LICENSE](LICENSE) para mais informações.
