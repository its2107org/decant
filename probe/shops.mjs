import { chromium } from 'playwright';
import fs from 'fs';
const shops = {
  'Astor Wines': 'astorwines.com', 'Flatiron Wines': 'flatiron-wines.com', 'Mister Wright A': 'misterwrightfinewines.com',
  'Mister Wright B': 'mrwrightwines.com', 'Mister Wright C': 'misterwright.com', 'K&L': 'klwines.com', 'Chambers Street': 'chambersstwines.com',
  'Sherry-Lehmann': 'sherry-lehmann.com', 'Morrell': 'morrellwine.com', 'Crush': 'crushwineco.com', 'Union Square Wines': 'unionsquarewines.com',
  'Garnet': 'garnetwine.com', '67 Wine': '67wine.com', 'Acker': 'ackerwines.com', 'Burgundy Wine Co': 'burgundywinecompany.com',
  'Bottlerocket': 'bottlerocketwine.com', 'Gotham Wines': 'gothamwines.com', 'PJ Wine': 'pjwine.com', 'Park Ave Liquor': 'parkaveliquor.com',
  'Italian Wine Merchants': 'italianwinemerchants.com', 'Le Du': 'leduwines.com', 'Discovery Wines': 'discoverywines.com',
  'Bowery and Vine': 'boweryandvine.com', 'Chelsea Wine Vault': 'chelseawinevault.com', 'Bottle Bargains': 'bottlebargains.com',
  'Wine Library': 'winelibrary.com', 'Zachys': 'zachys.com', 'Sokolin': 'sokolin.com'
};
const q = process.env.Q || 'Monte Bello';
fs.mkdirSync('out', { recursive: true });
const browser = await chromium.launch();
const results = [];
for (const [name, domain] of Object.entries(shops)) {
  const ctx = await browser.newContext({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1', viewport: { width: 390, height: 1800 } });
  const page = await ctx.newPage();
  const xhr = [];
  page.on('response', r => { const t = r.request().resourceType(); if ((t === 'xhr' || t === 'fetch') && (r.headers()['content-type'] || '').includes('json')) xhr.push(r.status() + ' ' + r.url().slice(0, 200)); });
  const res = { name, domain };
  try {
    const resp = await page.goto('https://www.' + domain, { waitUntil: 'domcontentloaded', timeout: 30000 });
    await page.waitForTimeout(3000);
    res.status = resp?.status(); res.url = page.url(); res.title = await page.title();
    const html = await page.content();
    res.platform = ['shopify', 'woocommerce', 'magento', 'bigcommerce', 'squarespace', 'wix', 'liquorsplit', 'cloudflare', 'challenge-platform', 'captcha', 'rapidbiz', 'wineandliquor', 'shopwine', 'bevsites', 'nextjs', '__NEXT_DATA__'].filter(k => html.toLowerCase().includes(k.toLowerCase()));
    if (res.platform.includes('shopify')) {
      res.suggest = await page.evaluate(async q => { try { const r = await fetch('/search/suggest.json?q=' + encodeURIComponent(q) + '&resources[type]=product&resources[limit]=5'); const j = await r.json(); return r.status + ' ' + JSON.stringify((j.resources?.results?.products || []).map(p => [p.title, p.price])); } catch (e) { return String(e); } }, q);
    }
    const box = page.locator('input[type="search"], input[name="q"], input[name*="search" i], input[placeholder*="earch" i]').first();
    try {
      if (!(await box.isVisible())) { const b = page.locator('[aria-label*="earch" i], button:has-text("Search"), a[href*="search"]').first(); await b.click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(800); }
      await box.fill(q, { timeout: 6000 }); await box.press('Enter');
      await page.waitForLoadState('domcontentloaded', { timeout: 20000 }).catch(() => {});
      await page.waitForTimeout(5000);
      res.searchURL = page.url();
      const text = await page.evaluate(() => document.body.innerText);
      res.priceLines = text.split('\n').map(s => s.trim()).filter(s => /\$\s?\d/.test(s)).slice(0, 8);
      res.mentions = (text.match(/monte bello/gi) || []).length;
      await page.screenshot({ path: `out/${domain}.png` });
    } catch (e) { res.searchError = String(e).slice(0, 200); }
  } catch (e) { res.error = String(e).slice(0, 200); }
  res.xhr = xhr.slice(0, 15);
  results.push(res);
  fs.writeFileSync('out/shops.json', JSON.stringify(results, null, 1));
  await ctx.close();
}
await browser.close();
