// Usage: node check-story-map.mjs <story-map.html> [screenshot-dir]
// Prints chip overlaps, chips on text, stories with no chip, unknown chip IDs, console errors,
// and the page width at 390px. Exits 1 when any check fails, and 2 when it cannot run.
//
// Needs puppeteer-core or puppeteer. The script imports "puppeteer-core", then "puppeteer". When Node
// cannot find either from this folder, set PUPPETEER_CORE to the entry file of an install.
// Chrome: set CHROME to a Chrome binary, or leave it unset to use the installed Google Chrome.
async function loadPuppeteer() {
  const candidates = [process.env.PUPPETEER_CORE, 'puppeteer-core', 'puppeteer'].filter(Boolean);
  for (const name of candidates) {
    try {
      return (await import(name)).default;
    } catch {}
  }
  console.error('Cannot load puppeteer. Install puppeteer-core, or set PUPPETEER_CORE to its entry file.');
  process.exit(2);
}
const puppeteer = await loadPuppeteer();
const file = new URL(process.argv[2], 'file://' + process.cwd() + '/').href;
const shots = process.argv[3];
const browser = await puppeteer.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : { channel: 'chrome' });
const page = await browser.newPage();
const errors = [];
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));
await page.setViewport({ width: 1700, height: 1100 });
await page.goto(file, { waitUntil: 'networkidle0' });
await new Promise((r) => setTimeout(r, 800));
const report = await page.evaluate(() => {
  const hit = (a, b) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
  const chips = [...document.querySelectorAll('#sm-chips .sm-chip')].map((g) => ({ id: g.dataset.story, b: g.getBBox() }));
  const texts = [...document.querySelectorAll('#sm-flow text')].filter((t) => !t.closest('#sm-chips') && !t.closest('.sm-legend'));
  const overlaps = [];
  chips.forEach((c, i) => chips.slice(i + 1).forEach((d) => { if (hit(c.b, d.b)) overlaps.push(c.id + ' / ' + d.id); }));
  const onText = [];
  chips.forEach((c) => texts.forEach((t) => { if (hit(c.b, t.getBBox())) onText.push(c.id + ' on "' + t.textContent.slice(0, 40) + '"'); }));
  const known = new Set(STORIES.map((s) => s.id));
  const chipped = new Set(chips.map((c) => c.id));
  return {
    chips: chips.length,
    overlaps,
    onText,
    storiesWithoutChip: [...known].filter((id) => !chipped.has(id)),
    unknownChips: [...chipped].filter((id) => !known.has(id)),
  };
});
if (shots) await page.screenshot({ path: shots + '/story-map.png', fullPage: true });
await page.setViewport({ width: 390, height: 900 });
await new Promise((r) => setTimeout(r, 300));
report.widthAt390 = await page.evaluate(() => document.documentElement.scrollWidth);
report.errors = errors;
console.log(JSON.stringify(report, null, 2));
await browser.close();
const failed = report.overlaps.length || report.onText.length || report.storiesWithoutChip.length
  || report.unknownChips.length || report.errors.length || report.widthAt390 > 390;
process.exit(failed ? 1 : 0);
