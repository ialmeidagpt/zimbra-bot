import * as soapService from '../services/soapService.js';
import { checkAllCertificates } from '../services/certService.js';
import { ensureFileExists, loadAddressIpData, saveAddressIpData } from '../services/fileService.js';
import { processAddresses } from '../services/addressService.js';

export async function main() {
  try {
    ensureFileExists();
    const authToken = await soapService.makeAuthRequest();
    const queue = await soapService.getMailQueue(authToken, process.env.HOSTNAME);

    if (!queue || !queue.qs || !queue.qi) {
      console.log('No queue data found.');
      await soapService.sendTelegramMessage('No queue data found.');
      return;
    }

    const qsFrom = queue.qs.find(q => q.$.type === 'from');
    const qsReceived = queue.qs.find(q => q.$.type === 'received');

    if (!qsFrom || !qsReceived) {
      console.log('No "from" or "received" type entries found.');
      await soapService.sendTelegramMessage('No "from" or "received" type entries found.');
      return;
    }

    const addressIpData = loadAddressIpData();
    await processAddresses({
      qsFrom,
      qiList: queue.qi,
      authToken,
      addressIpData
    });

    saveAddressIpData(addressIpData);

  } catch (error) {
    console.log('Error:', error);
    const errorMessage = soapService.formatError(error);
    await soapService.handleError(errorMessage);
  }
}
