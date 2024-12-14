import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Caminho para o arquivo JSON
const filePath = path.resolve(__dirname, '../address_ip_data.json');

export function ensureFileExists() {
  if (!fs.existsSync(filePath)) {
    fs.writeFileSync(filePath, JSON.stringify({}, null, 2));
  }
}

export function loadAddressIpData() {
  if (fs.existsSync(filePath)) {
    const rawData = fs.readFileSync(filePath);
    return JSON.parse(rawData);
  }
  return {};
}

export function saveAddressIpData(data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
}
