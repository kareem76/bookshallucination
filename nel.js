// scrape_books.js (Node.js version using Playwright)

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { chromium } = require('playwright');

const rate = 0.33;

async function extractBookData(page, url, genre, currentPageUrl) {
  try {
    const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
    if (!response || !response.ok()) throw new Error(`Failed to load ${url}`);

    const title = await page.$eval('div.p-title', el => el.textContent.trim());
    const author = await page.$eval('div.p-author', el => el.textContent.trim().replace(/^\u0644\u0640 /, ''));
    const image = await page.getAttribute('.p-cover img', 'src');
    const year = await page.$eval('.p-info b:has-text("\u062A\u0627\u0631\u064A\u062E \u0627\u0644\u0646\u0634\u0631") + span', el => el.textContent.trim()).catch(() => null);
    const publisher = await page.$eval('.p-info b:has-text("\u0627\u0644\u0646\u0627\u0634\u0631") + span', el => el.textContent.trim()).catch(() => null);
    const isbn = await page.$eval('.p-info b:has-text("\u0631\u062F\u0645\u0643") + span', el => el.textContent.trim()).catch(() => null);

    let summary = "null";
    try {
      summary = await page.$eval('span.desc.nabza d', d => {
        d.querySelectorAll('span').forEach(span => span.remove());
        return d.textContent.trim() || "null";
      });
    } catch {}

    let localPrice = null;
    try {
      const priceText = await page.$eval('b.ourprice', el => el.textContent.trim());
      localPrice = parseFloat(priceText.split(' ')[0]);
    } catch {}

    const usdPrice = localPrice ? Math.round(localPrice * rate) : null;
console.log(`📘 ${title} by ${author} | ${publisher || 'Unknown'} | $${usdPrice || 'N/A'}`);

    return {
      title, author, genre, book_url: url, image,
      year, publisher, summary, isbn, price_in_usd: usdPrice, page_url: currentPageUrl
    };
  } catch (err) {
    console.error(`Error scraping ${url}:`, err.message);
    return null;
  }
}

async function scrapeGenre(browser, categoryUrl, genre, outputPrefix) {
  const page = await browser.newPage();
  const books = [];

  await page.goto(categoryUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(3000);

  while (true) {
    const currentUrl = page.url();

    const bookLinks = await page.$$eval('.gridview .imggrid a', links =>
      links.map(link => link.href)
    );

    for (const bookUrl of bookLinks) {
      const data = await extractBookData(page, bookUrl, genre, currentUrl);
      if (data) books.push(data);
      await page.waitForTimeout(500); // Small delay between books
    }

    const nextBtn = await page.$('img[src$="arrowr.png"]');
    if (!nextBtn) break;

    await nextBtn.click();
    await page.waitForTimeout(5000); // Wait for next page to load
  }

  await page.close();

  const jsonPath = `${outputPrefix}-books.json`;
  fs.writeFileSync(jsonPath, books.map(b => JSON.stringify(b)).join('\n'), 'utf8');
  console.log(`✅ Saved ${books.length} books to ${jsonPath}`);
}

async function main() {
  const inputFile = process.argv[2] || 'links.txt';
  const outputPrefix = path.basename(inputFile, '.txt');

  const fileStream = fs.createReadStream(inputFile);
  const rl = readline.createInterface({ input: fileStream, crlfDelay: Infinity });

  const browser = await chromium.launch({ headless: true });

  for await (const line of rl) {
    const [url, genre] = line.trim().split(/\s+/, 2);
    if (!url || !genre) continue;
    console.log(`▶ Scraping books for genre: ${genre}`);
    await scrapeGenre(browser, url, genre, outputPrefix);
  }

  await browser.close();
}

main();
