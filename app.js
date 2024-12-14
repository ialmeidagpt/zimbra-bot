import { main } from './controllers/mainController.js';
import { checkAllCertificates } from './services/certService.js';

// Configurações de intervalo
const minutes = 10;
const interval = minutes * 60 * 1000;

// Executar a função main a cada 'interval' milissegundos
setInterval(main, interval);
// Executar a checagem de certificados a cada 8 horas
setInterval(checkAllCertificates, 8 * 60 * 60 * 1000);

// Execuções iniciais
main();
checkAllCertificates();
