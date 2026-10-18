// Looks at how Vinous search works, without signing in. Writes what it finds to out/.
import { chromium } from 'playwright';
import fs from 'fs';

const queries = (process.env.QUERIES || 'Evesham Wood Pinot Noir Willamette Valley 2024').split('|');
fs.mkdirSync('out', { recursive: true });
const browser = await chromium.launch();
const ctx = await browser.newContext({
  userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
  viewport: { width: 390, height: 2000 },
});
const log = [];
ctx.on('request', r => { if (['xhr', 'fetch', 'document'].includes(r.resourceType())) log.push({ m: r.method(), url: r.url(), post: r.postData()?.slice(0, 2000) }); });
ctx.on('response', async r => {
  const t = r.request().resourceType();
  if (!['xhr', 'fetch'].includes(t)) return;
  try {
    const body = await r.text();
    const name = 'out/resp-' + log.length + '-' + new URL(r.url()).pathname.replace(/[^a-z0-9]+/gi, '_').slice(0, 60) + '.txt';
    fs.writeFileSync(name, r.url() + '\n' + r.status() + '\n\n' + body.slice(0, 200000));
  } catch {}
});
const page = await ctx.newPage();
const settle = async () => { await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {}); await page.waitForTimeout(3000); };

await page.goto('https://vinous.com/wines', { waitUntil: 'domcontentloaded', timeout: 60000 });
await settle();
fs.writeFileSync('out/wines.html', await page.content());
fs.writeFileSync('out/wines.txt', await page.evaluate(() => document.body.innerText));
const inputs = await page.evaluate(() => [...document.querySelectorAll('input, textarea')].map(i => ({ type: i.type, name: i.name, id: i.id, ph: i.placeholder, cls: i.className, visible: !!(i.offsetWidth || i.offsetHeight) })));
fs.writeFileSync('out/inputs.json', JSON.stringify(inputs, null, 2));

let n = 0;
for (const q of queries) {
  n++;
  await page.goto('https://vinous.com/wines', { waitUntil: 'domcontentloaded', timeout: 60000 });
  await settle();
  const box = page.locator('input[type="search"], input[placeholder*="earch" i], input[name*="search" i], input[name="q"], input[type="text"]').first();
  try {
    await box.click({ timeout: 10000 });
    await box.fill(q);
    await page.waitForTimeout(1500);
    fs.writeFileSync(`out/q${n}-typing.txt`, await page.evaluate(() => document.body.innerText));
    await box.press('Enter');
  } catch (e) { fs.writeFileSync(`out/q${n}-error.txt`, String(e)); }
  await settle();
  fs.writeFileSync(`out/q${n}-url.txt`, page.url() + '\n' + q);
  fs.writeFileSync(`out/q${n}.txt`, await page.evaluate(() => document.body.innerText));
  fs.writeFileSync(`out/q${n}.html`, await page.content());
  await page.screenshot({ path: `out/q${n}.png`, fullPage: false });
}
fs.writeFileSync('out/requests.json', JSON.stringify(log, null, 2));
await browser.close();
