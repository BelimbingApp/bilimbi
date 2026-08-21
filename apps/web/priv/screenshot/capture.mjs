// Playwright driver for `mix bilimbi.screenshot` (#615). The Elixir task seeds
// the operator identity, grants, serves the endpoint and shells out to this
// script, which logs in through the real form (so the capture also smoke-tests
// auth), navigates to the requested route, and writes a PNG. It fails loud on a
// broken or blank route — the #409 discipline applies to tooling too.
//
// Everything is passed as SHOT_* env vars so no credential lands in argv/ps.
// playwright-core (no bundled browser) — we point at a chromium already in the
// Playwright cache, matching the visual-audit harness so outputs stay comparable.
import { chromium } from "playwright-core";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

function fail(message) {
  console.error(`bilimbi.screenshot: ${message}`);
  process.exit(1);
}

// The connected-mount morph can re-render the login form and clear an initial
// fill. Re-fill until the value survives a short settle, so the submit carries
// real credentials rather than an empty form.
async function fillStable(page, selector, value) {
  for (let attempt = 0; attempt < 15; attempt += 1) {
    await page.fill(selector, value);
    await page.waitForTimeout(150);
    if ((await page.inputValue(selector)) === value) return;
  }
  fail(`could not stably fill ${selector} (form keeps resetting)`);
}

// A cold connected mount can re-render the login form after the socket reports
// connected but before `phx-submit` is attached, so the first click falls
// through to the native `action="/session"` POST with an empty token and bounces
// back to login. Wait for connect, let the morph settle, then submit — and retry
// once, since the whole page reloads on that native bounce.
async function attemptLogin(page, baseUrl, email, password) {
  await page.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected(), null, {
    timeout: 20000,
  });
  await page.waitForSelector("#login-submit:not([disabled])", { timeout: 15000 });
  await page.waitForTimeout(400);
  await fillStable(page, "#login-email", email);
  await fillStable(page, "#login-password", password);
  await page.click("#login-submit");
  // Auth verifies an Argon2id hash (deliberately slow) and the cold server's
  // first request is slower still, so wait generously — long enough that a
  // slow-but-successful login is caught here rather than racing the retry.
  // `#login-opening` (phase :opening) appears only after auth succeeds.
  try {
    await Promise.race([
      page.waitForURL((url) => new URL(url).pathname !== "/", { timeout: 30000 }),
      page
        .waitForSelector("#login-opening", { timeout: 30000 })
        .then(() => page.waitForURL((url) => new URL(url).pathname !== "/", { timeout: 15000 })),
    ]);
    return true;
  } catch {
    return false;
  }
}

const env = process.env;
const baseUrl = env.SHOT_BASE_URL;
const route = env.SHOT_ROUTE;
const email = env.SHOT_EMAIL;
const password = env.SHOT_PASSWORD;
const outPath = env.SHOT_OUT;
const theme = env.SHOT_THEME === "dark" ? "dark" : "light";
const [vw, vh] = (env.SHOT_VIEWPORT || "1440x900").split("x").map((n) => parseInt(n, 10));

for (const [key, value] of Object.entries({
  SHOT_BASE_URL: baseUrl,
  SHOT_ROUTE: route,
  SHOT_EMAIL: email,
  SHOT_PASSWORD: password,
  SHOT_OUT: outPath,
})) {
  if (!value) fail(`missing ${key}`);
}

// Use a browser already in the Playwright cache so the harness never triggers a
// download on a reviewer's machine. Fall back to Playwright's own resolution.
function cachedExecutable() {
  const base = path.join(os.homedir(), ".cache", "ms-playwright");
  if (!fs.existsSync(base)) return undefined;
  const entries = fs.readdirSync(base);
  const candidates = [
    ...entries
      .filter((d) => d.startsWith("chromium_headless_shell-"))
      .sort()
      .reverse()
      .map((d) => path.join(base, d, "chrome-headless-shell-linux64", "chrome-headless-shell")),
    ...entries
      .filter((d) => d.startsWith("chromium-"))
      .sort()
      .reverse()
      .map((d) => path.join(base, d, "chrome-linux64", "chrome")),
  ];
  return candidates.find((p) => fs.existsSync(p));
}

const executablePath = cachedExecutable();
const browser = await chromium.launch(executablePath ? { executablePath } : {});

try {
  const context = await browser.newContext({
    viewport: { width: vw || 1280, height: vh || 900 },
    colorScheme: theme,
    deviceScaleFactor: 2,
  });
  const page = await context.newPage();
  const pageErrors = [];
  page.on("pageerror", (error) => pageErrors.push(String(error)));

  // 1) Log in through the real login form.
  const loginResponse = await page.goto(new URL("/", baseUrl).href, {
    waitUntil: "networkidle",
    timeout: 30000,
  });
  if (!loginResponse || !loginResponse.ok()) {
    fail(`login page returned HTTP ${loginResponse && loginResponse.status()}`);
  }

  let authenticated = await attemptLogin(page, baseUrl, email, password);
  if (!authenticated) {
    // The native bounce reloaded the login page; try once more now that the
    // LiveView is warm and its bindings are attached.
    await page.waitForLoadState("networkidle").catch(() => {});
    authenticated = await attemptLogin(page, baseUrl, email, password);
  }
  if (!authenticated) {
    const formError = await page
      .locator("#login-form-error, #login-session-expired")
      .allInnerTexts()
      .then((t) => t.join(" ").trim())
      .catch(() => "");
    fail(
      `login did not authenticate — still on ${new URL(page.url()).pathname}` +
        `${formError ? ` · ${formError}` : ""} (check ${["email", "password"].join("/")} env + dev seed)`,
    );
  }
  await page.waitForLoadState("networkidle");

  // 2) Navigate to the requested route.
  const response = await page.goto(new URL(route, baseUrl).href, {
    waitUntil: "networkidle",
    timeout: 30000,
  });
  if (!response) fail(`no response for ${route}`);
  if (response.status() >= 400) fail(`route ${route} returned HTTP ${response.status()}`);
  if (new URL(page.url()).pathname === "/") {
    fail(`route ${route} redirected to login — the seeded user lacks the required capability`);
  }

  // 3) Fail loud on a blank render rather than saving an empty "success".
  await page.waitForLoadState("networkidle");
  const bodyText = (await page.locator("body").innerText().catch(() => "")).trim();
  if (bodyText.length < 5) fail(`route ${route} rendered blank`);

  // The app shell is `h-screen` and scrolls `#app-content`, not the document,
  // so Playwright's `fullPage` clips below the fold. Grow the viewport to the
  // content's natural height so the whole screen — sidebar included — is one
  // faithful image.
  const neededHeight = await page.evaluate(() => {
    const content = document.querySelector("#app-content");
    const topbar = document.querySelector("#app-topbar");
    const top = topbar ? topbar.offsetHeight : 0;
    return Math.ceil(Math.max(content ? content.scrollHeight + top : 0, document.body.scrollHeight));
  });
  const captureHeight = Math.min(Math.max(neededHeight, vh || 900), 12000);
  await page.setViewportSize({ width: vw || 1280, height: captureHeight });
  await page.waitForTimeout(400);

  await fs.promises.mkdir(path.dirname(outPath), { recursive: true });
  await page.screenshot({ path: outPath, fullPage: true });

  const errorNote = pageErrors.length ? ` (page errors: ${pageErrors.length})` : "";
  console.log(`bilimbi.screenshot: wrote ${outPath} — HTTP ${response.status()} ${page.url()}${errorNote}`);
} finally {
  await browser.close();
}
