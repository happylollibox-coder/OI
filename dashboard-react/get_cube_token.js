const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext();
  const page = await context.newPage();
  
  const apiErrors = [];
  page.on('response', async request => {
    if (request.url().includes('/cubejs-api/')) {
       if (request.status() >= 400) {
         try {
           const body = await request.text();
           apiErrors.push({ url: request.url(), status: request.status(), body: body || '(empty body)' });
         } catch (e) {
           apiErrors.push({ url: request.url(), status: request.status(), error: e.message });
         }
       }
    }
  });

  try {
    await page.goto('https://oi-dashboard-405291422506.us-central1.run.app/', { waitUntil: 'networkidle' });
    await page.waitForTimeout(5000); // 5s to ensure cube completes
    console.log(JSON.stringify(apiErrors, null, 2));
  } catch(e) { console.error('Playwright Error:', e); }
  await browser.close();
})();
