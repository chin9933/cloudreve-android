// Optional read-only connectivity probe. Never run against a site without consent.
// Environment: CLOUDREVE_SITE_URL; optional CLOUDREVE_ACCESS_TOKEN.
// Only status codes are printed, never response bodies, tokens or file names.
const input = process.env.CLOUDREVE_SITE_URL;
if (!input) throw new Error('Set CLOUDREVE_SITE_URL to an authorized HTTPS server.');
const site = new URL(input);
if (site.protocol !== 'https:' || site.username || site.password) {
  throw new Error('An HTTPS URL without embedded credentials is required.');
}
site.search = '';
site.hash = '';
site.pathname = site.pathname.replace(/\/$/, '').replace(/\/api\/v4$/, '') + '/api/v4/';

const headers = {};
if (process.env.CLOUDREVE_ACCESS_TOKEN) {
  headers.Authorization = `Bearer ${process.env.CLOUDREVE_ACCESS_TOKEN}`;
}
const endpoints = ['site/config/basic'];
if (headers.Authorization) endpoints.push('devices/dav?page_size=1');
for (const endpoint of endpoints) {
  try {
    const response = await fetch(new URL(endpoint, site), {
      headers,
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
    });
    const result = await response.json();
    console.log(JSON.stringify({ endpoint, httpStatus: response.status, code: result.code }));
    if (!response.ok || result.code !== 0) process.exitCode = 1;
  } catch {
    console.error(`Probe failed for ${endpoint}; response details are intentionally omitted.`);
    process.exitCode = 1;
  }
}
