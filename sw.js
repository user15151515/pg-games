// pgfantasy.cat era PG Fantasy (app con service worker en /sw.js). Desde el 26/11/2026 aquí está pg games, que no usa
// service worker. Los navegadores que tenían instalado el de PG Fantasy buscan actualizaciones en esta misma URL:
// esta versión borra su caché de imágenes y se desinstala sola, sin recargar ninguna página. No lo borres.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    try { const ks = await caches.keys(); await Promise.all(ks.filter(k => k.startsWith('claret-')).map(k => caches.delete(k))); } catch (e) {}
    try { await self.registration.unregister(); } catch (e) {}
  })());
});
