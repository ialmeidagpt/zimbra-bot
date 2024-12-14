import https from 'https';
import dotenv from 'dotenv';
import * as soapService from './soapService.js';

dotenv.config();

const sites = process.env.SITES.split(',');

async function getCertificateExpireDate(hostname, port = 443) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: hostname,
      port: port,
      method: 'GET',
      rejectUnauthorized: false,
    };

    const req = https.request(options, (res) => {
      const certificate = res.connection.getPeerCertificate();
      if (certificate && certificate.valid_to) {
        const expireDate = new Date(certificate.valid_to);
        resolve(expireDate);
      } else {
        reject(new Error('Unable to retrieve certificate information.'));
      }
    });

    req.on('error', (e) => {
      reject(e);
    });

    req.end();
  });
}

function isExpiringWithin7Days(expireDate) {
  const now = new Date();
  const diffTime = expireDate - now;
  const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
  return diffDays <= 7;
}

export async function checkAllCertificates() {
  for (const site of sites) {
    const [hostname, port] = site.trim().split(':');
    try {
      const expireDate = await getCertificateExpireDate(hostname, port ? parseInt(port) : 443);
      if (isExpiringWithin7Days(expireDate)) {
        console.log(`The certificate for ${hostname}${port ? `:${port}` : ''} is expiring on ${expireDate.toUTCString()}`);
        await soapService.sendTelegramMessage(`The certificate for ${hostname}${port ? `:${port}` : ''} is expiring on ${expireDate.toUTCString()}`);
      }
    } catch (error) {
      console.error(`Failed to check certificate for ${hostname}${port ? `:${port}` : ''}:`, error);
      await soapService.sendTelegramMessage(`Failed to check certificate for ${hostname}${port ? `:${port}` : ''}: ${error.message}`);
    }
  }
}
