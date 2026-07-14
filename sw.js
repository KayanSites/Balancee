// Balancee — service worker
// بيخزّن ملفات التطبيق عشان يفتح من غير نت (الداتا نفسها محتاجة نت لو على Supabase)
const CACHE = 'balancee-v1';
const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './logo-full.png',
  './logo-mark.png',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET') return;
  // نداءات Supabase تعدي على النت على طول — عمرها ما تتكاش
  if (url.hostname.endsWith('supabase.co')) return;

  e.respondWith(
    caches.match(e.request).then(hit =>
      hit || fetch(e.request).then(res => {
        if (res.ok && url.origin === location.origin){
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(e.request, copy));
        }
        return res;
      }).catch(() => caches.match('./index.html'))
    )
  );
});
