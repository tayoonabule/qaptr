import { chromium } from "playwright";

const url = process.argv[2] || "http://localhost:8900/";
const outfile = process.argv[3] || "/tmp/shots/shot.png";
const width = parseInt(process.argv[4] || "1440", 10);
const height = parseInt(process.argv[5] || "900", 10);
const fullPage = process.argv[6] === "full";

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width, height } });
await page.goto(url, { waitUntil: "networkidle" });
await page.screenshot({ path: outfile, fullPage });
await browser.close();
console.log("saved", outfile);
