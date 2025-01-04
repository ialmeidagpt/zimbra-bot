import * as soapService from "./soapService.js";

// Variáveis de ambiente
const greaterThanCounter = process.env.SPAM_THRESHOLD;
const knownEmailServices = (process.env.KNOWN_EMAIL_SERVICES || "").split(",");
const nativeDomain = process.env.NATIVE_DOMAIN || "";

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
    const count = qsi.$.n;

    if (!fromAddress.includes("@")) {
      console.log(`Invalid email address: ${fromAddress}, skipping...`);
      continue;
    }

    const ip = ipMap.get(fromAddress) || null;

    // Caso crítico: IP não encontrado e envio excessivo
    if (fromAddress.includes(nativeDomain) && !ip && count > greaterThanCounter) {
      await handleCriticalCase(authToken, fromAddress, count);
      continue;
    }

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

    console.log(
      `fromAddress: ${fromAddress}, isForeign: ${isForeign}, greaterThanCounter > ${greaterThanCounter}: ${count}, isKnownService: ${isKnownService}, isIpNew: ${isIpNew}`
    );

    // Condições normais: bloqueio para envio estrangeiro e IP novo
    if (
      fromAddress.includes(nativeDomain) &&
      isForeign &&
      count > greaterThanCounter &&
      !isKnownService &&
      isIpNew
    ) {
      await handleBlocking(authToken, fromAddress, ip, country, count);
    } else if (count > greaterThanCounter) {
      // Caso alternativo: apenas troca a senha
      await handlePasswordChange(authToken, fromAddress, count);
    }

    if (isIpNew && ip) {
      addressIpData[fromAddress].push(ip);
    }
  }
}

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

async function handleCriticalCase(authToken, fromAddress, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);
    const setPassword = await soapService.setPassword(authToken, zimbraId);
    const bloquear = await bloquearConta(fromAddress);
    const observacao = await adicionarObservacao(fromAddress);

    let message =
      `*Address:* ${fromAddress},\n*Count:* ${count},\n*IP origem:* IP não encontrado (CRÍTICO).` +
      `,\n*Nova senha*: ${setPassword},` +
      `\n*Bloqueado*: ${bloquear},` +
      `\n*Observação*: ${observacao}`;
    console.warn(
      `Bloqueio e alteração de senha para ${fromAddress} devido a envio excessivo e IP não encontrado.`
    );
    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

async function handleBlocking(authToken, fromAddress, ip, country, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);
    const setPassword = await soapService.setPassword(authToken, zimbraId);

    let message = `*Address:* ${fromAddress},\n*Count:* ${count},\n*IP origem:* ${ip}${country !== "BR" ? " (estrangeiro: " + country + ")" : ""
      }`;
    const bloquear = await bloquearConta(fromAddress);
    const observacao = await adicionarObservacao(fromAddress);

    if (setPassword !== undefined) {
      message += `,\n*Nova senha*: ${setPassword}`;
    }

    message += `,\n*Bloqueado*: ${bloquear}`;
    message += `,\n*Observação*: ${observacao}`;

    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

async function handlePasswordChange(authToken, fromAddress, count) {
  try {
    const zimbraId = await soapService.getAccountInfo(authToken, fromAddress);
    const setPassword = await soapService.setPassword(authToken, zimbraId);

    let message = `*Address:* ${fromAddress},\n*Count:* ${count},\n*Nova senha*: ${setPassword}`;
    console.warn(`Senha alterada para ${fromAddress} devido a envio excessivo.`);
    await soapService.sendTelegramMessage(message);
  } catch (error) {
    await handleAccountError(error, fromAddress);
  }
}

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
