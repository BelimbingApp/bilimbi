// PDF-only runner. Node >=22, sandboxed Chromium, qpdf >=10.6; no npm modules.
// All input and errors stay private. Only the fixed exit code crosses the port.
import { spawn } from "node:child_process";
import { chmod, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const request = JSON.parse(await readFile(process.argv[2], "utf8"));
let child;
function cleanup() {
  if (child?.pid) {
    try { process.kill(-child.pid, "SIGKILL"); } catch { /* already gone */ }
  }
}
function finish(code) { cleanup(); process.exit(code); }
process.on("SIGTERM", () => finish(1));
process.on("SIGHUP", () => finish(1));
process.on("uncaughtException", () => finish(1));
process.on("unhandledRejection", () => finish(1));
setTimeout(() => finish(124), request.timeoutMs);

async function protect() {
  const dir = dirname(process.argv[2]);
  const input = join(dir, "source.pdf");
  const job = join(dir, "qpdf.json");
  await writeFile(input, Buffer.from(request.bytes, "base64"), { mode: 0o600, flag: "wx" });
  await writeFile(job, JSON.stringify({
    inputFile: input, outputFile: request.output,
    encrypt: { userPassword: request.password, ownerPassword: request.ownerPassword, "256bit": {} }
  }), { mode: 0o600, flag: "wx" });
  child = spawn(request.binary, [`--job-json-file=${job}`], { detached: true, stdio: "ignore" });
  const code = await new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", resolve);
  });
  if (code !== 0) throw new Error();
  await chmod(request.output, 0o600);
}

async function render() {
  const paper = { A4: [8.2677, 11.6929], A3: [11.6929, 16.5354], A5: [5.8268, 8.2677],
    Letter: [8.5, 11], Legal: [8.5, 14], Tabloid: [11, 17] }[request.format];
  if (!paper) throw new Error();
  child = spawn(request.binary, ["--headless", "--remote-debugging-pipe",
    "--disable-background-networking", "--disable-extensions", "--disable-sync",
    "--no-first-run", "--no-default-browser-check", "--disable-dev-shm-usage",
    `--user-data-dir=${join(dirname(process.argv[2]), "profile")}`, "about:blank"],
    { detached: true, stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"] });
  child.once("error", () => finish(1));
  child.once("exit", () => finish(1));
  let sequence = 0;
  let buffer = Buffer.alloc(0);
  const pending = new Map();
  let onEvent = () => {};
  function command(method, params = {}, sessionId) {
    const id = ++sequence;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      child.stdio[3].write(JSON.stringify({ id, method, params, sessionId }) + "\0");
    });
  }
  child.stdio[4].on("data", chunk => {
    buffer = Buffer.concat([buffer, chunk]);
    if (buffer.length > Math.max(request.maxBytes * 2, 1024 * 1024)) finish(1);
    let end;
    while ((end = buffer.indexOf(0)) !== -1) {
      const message = JSON.parse(buffer.subarray(0, end).toString());
      buffer = buffer.subarray(end + 1);
      if (message.id) {
        const response = pending.get(message.id);
        pending.delete(message.id);
        if (message.error) response?.reject(new Error());
        else response?.resolve(message.result);
      } else onEvent(message);
    }
  });
  const { targetId } = await command("Target.createTarget", { url: "about:blank" });
  const { sessionId } = await command("Target.attachToTarget", { targetId, flatten: true });
  const send = (method, params) => command(method, params, sessionId);
  let loaded;
  const load = new Promise(resolve => { loaded = resolve; });
  if (request.source === "url") request.value = new URL(request.value).href;
  let initialRequest = false;
  let status;
  onEvent = message => {
    if (message.sessionId !== sessionId) return;
    if (message.method === "Page.loadEventFired") loaded();
    if (message.method === "Network.responseReceived" && message.params.type === "Document") {
      status = message.params.response.status;
    }
    if (message.method === "Fetch.requestPaused") {
      const event = message.params;
      // Exactly one signed document request. Deny redirects, remote resources,
      // local files and all additional navigation; embedded data resources work.
      const allowed = request.source === "url" && !initialRequest &&
        event.resourceType === "Document" && event.request.url === request.value;
      if (allowed) initialRequest = true;
      send(allowed ? "Fetch.continueRequest" : "Fetch.failRequest",
        { requestId: event.requestId, ...(allowed ? {} : { errorReason: "BlockedByClient" }) }).catch(() => finish(1));
    }
  };
  await send("Page.enable");
  await send("Network.enable");
  await send("Emulation.setScriptExecutionDisabled", { value: true });
  await send("Browser.setDownloadBehavior", { behavior: "deny" });
  await send("Fetch.enable", { patterns: [{ urlPattern: "*", requestStage: "Request" }] });
  await send("Emulation.setEmulatedMedia", { media: "print" });
  if (request.source === "url") {
    const navigation = await send("Page.navigate", { url: request.value });
    if (navigation.errorText) throw new Error();
    await load;
    if (status !== 200) throw new Error();
  } else {
    const { frameTree } = await send("Page.getFrameTree");
    await send("Page.setDocumentContent", { frameId: frameTree.frame.id, html: request.value });
    await load;
  }
  // Script execution is disabled for templates. This CDP evaluation only waits
  // for embedded fonts to finish; no document-provided script is run.
  await send("Runtime.evaluate", { expression: "document.fonts.ready", awaitPromise: true });
  const { data } = await send("Page.printToPDF", { printBackground: request.printBackground,
    paperWidth: paper[0], paperHeight: paper[1], preferCSSPageSize: false,
    marginTop: 0.3937, marginBottom: 0.3937, marginLeft: 0.3937, marginRight: 0.3937 });
  const bytes = Buffer.from(data, "base64");
  if (!bytes.length || bytes.length > request.maxBytes) throw new Error();
  await writeFile(request.output, bytes, { mode: 0o600, flag: "wx" });
}
try {
  if (request.tool === "qpdf") await protect();
  else if (request.tool === "chromium") await render();
  else throw new Error();
  finish(0);
} catch { finish(1); }
