import { chromium } from 'playwright';
import fs from 'fs';
const cases = [
  ['Lopez de Heredia', 2012],
  ['Tondonia', 2012],
  ['Bollinger Special Cuvee', 0],
  ['Krug Grande Cuvee', 0],
  ['Domaine Leflaive', 2019],
  ['Evesham Wood', 2024],
  ['Ridge Monte Bello', 2018],
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
for (const [t,v] of [['Evesham Wood',2024],['Ridge Monte Bello',2018]]) {
  const b = await page.evaluate(async ([t,v]) => (await fetch('/api/v2/wines?' + new URLSearchParams({term:t, vintage:v, page:'1', per_page:'25'}))).text(), [t,v]);
  fs.writeFileSync('out/raw-' + t.replace(/ /g,'_') + '.json', b);
}
await page.goto('https://vinous.com/wines/evesham-wood-2024-pinot-noir-willamette-valley', { waitUntil: 'domcontentloaded', timeout: 60000 });
await page.waitForTimeout(6000);
fs.writeFileSync('out/winepage.txt', page.url() + '\n\n' + await page.evaluate(() => document.body.innerText));
fs.writeFileSync('out/api.json', JSON.stringify(out, null, 1));
await browser.close();
