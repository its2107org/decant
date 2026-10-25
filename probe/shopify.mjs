import fs from 'fs';
const shops = ['chambersstwines.com', 'crushwineco.com', '67wine.com', 'pjwine.com', 'zachys.com', 'flatiron-wines.com'];
const queries = ['Ridge Monte Bello', 'Monte Bello', 'Evesham Wood', 'Chateau Margaux', 'Bollinger Special Cuvee', 'Lopez de Heredia Tondonia', 'Tondonia', 'Domaine Tempier Bandol Rose', 'Barolo 2019'];
const UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
fs.mkdirSync('out', { recursive: true });
const out = {};
for (const shop of shops) {
  out[shop] = {};
  for (const q of queries) {
    const url = `https://${shop}/search/suggest.json?q=${encodeURIComponent(q)}&resources[type]=product&resources[limit]=10&resources[options][unavailable_products]=last&resources[options][fields]=title,product_type,variants.title,vendor`;
    try {
      const r = await fetch(url, { headers: { 'User-Agent': UA, Accept: 'application/json' } });
      const t = await r.text();
      let rows = [];
      try { const j = JSON.parse(t); const ps = j.resources?.results?.products || []; rows = ps.map(p => [p.title, p.price, p.available, p.url, p.vendor]); if (q === queries[0] && ps[0]) out[shop]._sample = ps[0]; } catch { rows = t.slice(0, 200); }
      out[shop][q] = { status: r.status, rows };
    } catch (e) { out[shop][q] = String(e); }
  }
  // also the full search page JSON alternative
  try { const r = await fetch(`https://${shop}/search?q=Monte+Bello&type=product&view=json`, { headers: { 'User-Agent': UA } }); out[shop]._searchView = r.status + ' ' + (await r.text()).slice(0, 150); } catch (e) {}
}
fs.writeFileSync('out/shopify.json', JSON.stringify(out, null, 1));
