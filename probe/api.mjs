import { chromium } from 'playwright';
import fs from 'fs';
const cases = [
  ['Evesham Wood Willamette Valley Pinot Noir', 2024],
  ['Evesham Wood Pinot Noir', 2024],
  ['Evesham Wood', 2024],
  ['Evesham Wood Willamette Valley Pinot Noir', 2019],
  ['Ridge Vineyards Monte Bello', 2018],
  ['Ridge Monte Bello', 2018],
  ['Chateau Margaux', 2015],
  ['Château Margaux Grand Vin', 2015],
  ['Domaine Leflaive Puligny-Montrachet Les Pucelles', 2019],
  ['Produttori del Barbaresco Barbaresco', 2019],
  ['Lopez de Heredia Vina Tondonia Reserva', 2012],
  ['R. Lopez de Heredia Viña Tondonia Reserva Tinto', 2012],
  ['Bollinger Special Cuvee', null],
  ['Domaine Tempier Bandol Rose', 2024],
  ['Felsina Chianti Classico Riserva Rancia', 2020],
  ['Evesham Wood Pinot Noir Willamette Valley', null],
];
fs.mkdirSync('out', { recursive: true });
const browser = await chromium.launch();
const page = await (await browser.newContext()).newPage();
await page.goto('https://vinous.com/wines', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(3000);
const out = [];
for (const [term, vintage] of cases) {
  const r = await page.evaluate(async ([term, vintage]) => {
    const p = new URLSearchParams({ term, vintage: vintage ?? '', order: '', order_type: 'desc', page: '1', per_page: '25' });
    const res = await fetch('/api/v2/wines?' + p, { credentials: 'include', headers: { Accept: 'application/json' } });
    return { status: res.status, body: await res.text() };
  }, [term, vintage]);
  let rows = [];
  try { const j = JSON.parse(r.body); rows = j.wines.map(w => ({ p: w._source.producer?.producer_name, n: w._source.wine_name, n2: w._source.wine_name_2, v: w._source.vintage, r: w._source.region_1, c: w._source.color, a: w._source.author, s: w._source.score, slug: w._source.slug })); out.push({ term, vintage, status: r.status, total: j.wines_total, rows }); }
  catch { out.push({ term, vintage, status: r.status, raw: r.body.slice(0, 500) }); }
}
// Also: plain fetch from Node, no browser
try { const res = await fetch('https://vinous.com/api/v2/wines?term=Evesham+Wood&vintage=2024&page=1&per_page=5'); out.push({ node: res.status, body: (await res.text()).slice(0, 300) }); } catch (e) { out.push({ node: String(e) }); }
fs.writeFileSync('out/api.json', JSON.stringify(out, null, 1));
await browser.close();
