// Aura: serviço mínimo para o painel poder ser instalado como aplicativo. Não guarda nada em cache.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
