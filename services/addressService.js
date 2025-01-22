import * as soapService from "./soapService.js";

// Variáveis de ambiente
const greaterThanCounter = Number(process.env.SPAM_THRESHOLD); // Garantir que seja numérico
const knownEmailServices = (process.env.KNOWN_EMAIL_SERVICES || "").split(",");
const nativeDomain = process.env.NATIVE_DOMAIN || "";
const ignoredEmails = (process.env.IGNORED_EMAILS || "").split(",").map(email => email.trim());
const ipThreshold = Number(process.env.IP_THRESHOLD || 1);

// Função para bloquear conta
async function bloquearConta(email) {
  try {
    const authToken = await soapService.makeAuthRequest();
    const zimbraId = await soapService.getAccountInfo(authToken, email);
    return await soapService.setAccountStatusBlocked(authToken, zimbraId);
  } catch (error) {
    const errorMessage = error?.message || "Erro desconhecido";
    console.error("Erro ao bloquear a conta:", errorMessage);
    await soapService.sendTelegramMessage(
      `Erro ao bloquear a conta: ${errorMessage}`
    );
  }
}

// Função para adicionar observação
async function adicionarObservacao(email) {
  try {
    const authToken = await soapService.makeAuthRequest();
    const zimbraId = await soapService.getAccountInfo(authToken, email);
    const currentDate = new Date().toLocaleDateString("pt-BR");
    const newObservation = `Email bloqueado em ${currentDate} (spam)`;
    return await soapService.addObservation(authToken, zimbraId, newObservation);
  } catch (error) {
    const errorMessage = error?.message || "Erro desconhecido";
    console.error("Erro ao adicionar observação:", errorMessage);
    await soapService.sendTelegramMessage(
      `Erro ao adicionar a observação: ${errorMessage}`
    );
  }
}

// Função principal para processar endereços
export async function processAddresses({
  qsFrom,
  qiList,
  authToken,
  addressIpData,
}) {
  const ipMap = mapIPs(qiList);
  const qsiList = qsFrom.qsi;

  for (const qsi of qsiList) {
    const fromAddress = qsi.$.t;
    const count = Number(qsi.$.n); // Garantir que count seja numérico

    // Ignorar e-mails listados em IGNORED_EMAILS
    if (ignoredEmails.includes(fromAddress)) {
      console.log(`Ignored email address: ${fromAddress}, skipping...`);
      continue;
    }

    if (!fromAddress.includes("@")) {
      console.log(`Invalid email address: ${fromAddress}, skipping...`);
      continue;
    }

    // Verificar múltiplos IPs associados no addressIpData
    if (addressIpData[fromAddress] && addressIpData[fromAddress].length > ipThreshold) {
      console.log(
        `Bloqueando ${fromAddress} por ter múltiplos IPs associados no addressIpData.`
      );

      // Verificar se o e-mail já está bloqueado para evitar trocas repetidas de senha
      // const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);
      // console.log(zimbraId)
      // if (!zimbraId) {
      //   console.log(`Conta ${fromAddress} já está bloqueada, ignorando troca de senha.`);
      //   continue;
      // }

      const ip = addressIpData[fromAddress][
        addressIpData[fromAddress].length - 1
      ]; // Pega o último IP associado
      const geoData = await soapService.getGeolocation(ip); // Obtém dados do IP para mensagem
      const country = geoData ? geoData.country : "unknown";
      await handleBlocking(authToken, fromAddress, ip, country, count);
      continue; // Ignorar processamento adicional após o bloqueio
    }

    const ip = ipMap.get(fromAddress) || null;
    const geoData = ip ? await soapService.getGeolocation(ip) : null;
    const country = geoData ? geoData.country : "unknown";
    const isForeign = country !== "BR";

    const hostname = geoData?.hostname || "";
    const isKnownService = knownEmailServices.some((service) =>
      hostname.includes(service)
    );

    if (!addressIpData[fromAddress]) {
      addressIpData[fromAddress] = [];
    }

    const isIpNew = ip && !addressIpData[fromAddress].includes(ip);

    // Logs detalhados
    console.log({
      fromAddress,
      count,
      greaterThanCounter,
      isForeign,
      isKnownService,
      isIpNew,
    });

    const action = classifyRemetente({
      fromAddress,
      count,
      ip,
      isForeign,
      isKnownService,
      isIpNew,
      greaterThanCounter,
      nativeDomain,
    });

    // Executar a ação correspondente
    switch (action) {
      case "critical":
        await handleCriticalCase(authToken, fromAddress, count);
        break;
      case "block":
        await handleBlocking(authToken, fromAddress, ip, country, count);
        break;
      case "changePassword":
        await handlePasswordChange(authToken, fromAddress, count);
        break;
      case "internalWarn":
        await handleInternalWarn(authToken, fromAddress, count);
        break;
      default:
        console.log(`Nenhuma ação necessária para: ${fromAddress}`);
    }

    // Atualizar IPs do endereço
    if (isIpNew && ip) {
      addressIpData[fromAddress].push(ip);
    }
  }
}

// Mapeamento de IPs
function mapIPs(qiList) {
  const ipMap = new Map();
  qiList.forEach((qi) => {
    const fromAddress = qi.$.from;
    const receivedIp = qi.$.received;
    if (fromAddress && receivedIp) {
      ipMap.set(fromAddress, receivedIp);
    }
  });
  return ipMap;
}

// Lidar com casos críticos
async function handleCriticalCase(authToken, fromAddress, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);

    if (!zimbraId) {
      console.log(`Conta inexistente para handleCriticalCase: ${fromAddress}`);
      return;
    }

    const newPassword = await soapService.setPassword(authToken, zimbraId);
    const bloquear = await bloquearConta(fromAddress);
    const observacao = await adicionarObservacao(fromAddress);

    let message = `*Address:* ${fromAddress},\n*Count:* ${count},\n*IP origem:* IP não encontrado (CRÍTICO).`;

    if (newPassword) {
      message += `,\n*Nova senha*: ${newPassword}`;
    }
    message += `,\n*Bloqueado*: ${bloquear},\n*Observação*: ${observacao}`;

    console.warn(`Ação crítica executada para ${fromAddress}`);
    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

// Lidar com bloqueio
async function handleBlocking(authToken, fromAddress, ip, country, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);

    if (!zimbraId) {
      console.log(`Conta inexistente para handleBlocking: ${fromAddress}`);
      return;
    }

    const newPassword = await soapService.setPassword(authToken, zimbraId);

    let message = `*Address:* ${fromAddress},\n*Count:* ${count},\n*IP origem:* ${ip}${country !== "BR" ? ` (estrangeiro: ${country})` : ""
      }`;

    const bloquear = await bloquearConta(fromAddress);
    const observacao = await adicionarObservacao(fromAddress);

    if (newPassword) {
      message += `,\n*Nova senha*: ${newPassword}`;
    }
    message += `,\n*Bloqueado*: ${bloquear},\n*Observação*: ${observacao}`;

    console.warn(`Conta bloqueada: ${fromAddress}`);
    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

// Lidar com troca de senha
async function handlePasswordChange(authToken, fromAddress, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);

    if (!zimbraId) {
      console.log(`Conta inexistente para handlePasswordChange: ${fromAddress}`);
      return;
    }

    const newPassword = await soapService.setPassword(authToken, zimbraId);
    if (!newPassword) {
      console.log(`Senha não trocada para: ${fromAddress}`);
      return;
    }

    let message = `*Address:* ${fromAddress},\n*Count:* ${count},\n*Nova senha*: ${newPassword}`;
    console.warn(`Senha alterada para ${fromAddress}`);
    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

// Lidar com erros de conta
async function handleAccountError(error, fromAddress) {
  if (error.message.includes("no such account")) {
    console.log(`No such account for email: ${fromAddress}`);
    await soapService.sendTelegramMessage(
      `No such account for email: ${fromAddress}`
    );
  } else {
    throw error;
  }
}

// Classificar remetente
function classifyRemetente({
  fromAddress,
  count,
  ip,
  isForeign,
  isKnownService,
  isIpNew,
  greaterThanCounter,
  nativeDomain,
}) {
  if (fromAddress.includes(nativeDomain) && !ip && count > greaterThanCounter) {
    return "critical";
  }

  if (
    fromAddress.includes(nativeDomain) &&
    isForeign &&
    count > greaterThanCounter &&
    !isKnownService &&
    isIpNew
  ) {
    return "block";
  }

  if (count > greaterThanCounter) {
    return "changePassword";
  }

  if (fromAddress.includes(nativeDomain) && count > greaterThanCounter) {
    return "internalWarn";
  }

  return "none";
}

// Enviar aviso interno
async function handleInternalWarn(authToken, fromAddress, count) {
  let message = `*Aviso*: A conta interna \`${fromAddress}\` já enviou *${count}* e-mails.\nVerifique se é spam ou envio legítimo.`;

  console.warn(`Aviso interno: ${fromAddress} já enviou ${count} e-mails.`);
  await soapService.sendTelegramMessage(message);
}
