#!/usr/bin/env node
/**
 * Centurion Mission Deck server
 * - Serves built SPA from dist/
 * - POST /api/bridge → python -m centurion_cli.remote_bridge (stdio JSON)
 * - GET /api/stream → SSE of life_thoughts_list (local poll, no cloud)
 *
 * Port 9120 — Brain LAN only, no auth.
 */
import http from "node:http";
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { randomUUID } from "node:crypto";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.MISSION_DECK_PORT || 9120);
const HOST = process.env.MISSION_DECK_HOST || "0.0.0.0";
const DEV = process.argv.includes("--dev");
const DIST = path.join(__dirname, "dist");
const REPO_ROOT = path.resolve(__dirname, "..");

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".map": "application/json",
};

function findPython() {
  const candidates = [
    process.env.CENTURION_PYTHON,
    path.join(REPO_ROOT, ".venv", "bin", "python"),
    path.join(REPO_ROOT, "venv", "bin", "python"),
    "python3",
    "python",
  ].filter(Boolean);
  for (const c of candidates) {
    if (c === "python3" || c === "python") return c;
    if (fs.existsSync(c)) return c;
  }
  return "python3";
}

const PYTHON = findPython();

/**
 * Invoke remote_bridge once with a JSON request object.
 * @param {Record<string, unknown>} request
 * @returns {Promise<Record<string, unknown>>}
 */
function callBridge(request) {
  return new Promise((resolve, reject) => {
    const child = spawn(PYTHON, ["-m", "centurion_cli.remote_bridge"], {
      cwd: REPO_ROOT,
      env: { ...process.env, PYTHONUNBUFFERED: "1" },
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error("bridge timeout"));
    }, 30_000);

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (err) => {
      clearTimeout(timer);
      reject(err);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      const line = stdout
        .split("\n")
        .map((l) => l.trim())
        .filter(Boolean)
        .pop();
      if (!line) {
        reject(
          new Error(
            `bridge empty response (code=${code}): ${stderr.slice(0, 400)}`,
          ),
        );
        return;
      }
      try {
        resolve(JSON.parse(line));
      } catch (e) {
        reject(
          new Error(
            `bridge invalid JSON: ${line.slice(0, 200)} | ${stderr.slice(0, 200)}`,
          ),
        );
      }
    });

    child.stdin.write(JSON.stringify(request));
    child.stdin.end();
  });
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (c) => chunks.push(c));
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf8");
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("invalid JSON body"));
      }
    });
    req.on("error", reject);
  });
}

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  });
  res.end(body);
}

function serveStatic(req, res) {
  if (DEV) {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(
      "Mission Deck API running in --dev mode. Use Vite at http://localhost:5173\n",
    );
    return;
  }

  let urlPath = decodeURIComponent((req.url || "/").split("?")[0]);
  if (urlPath === "/") urlPath = "/index.html";
  const filePath = path.normalize(path.join(DIST, urlPath));
  if (!filePath.startsWith(DIST)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      // SPA fallback
      fs.readFile(path.join(DIST, "index.html"), (err2, html) => {
        if (err2) {
          res.writeHead(404);
          res.end("Not found — run npm run build first");
          return;
        }
        res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
        res.end(html);
      });
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
    res.end(data);
  });
}

async function handleBridge(req, res) {
  try {
    const body = await readBody(req);
    const request = {
      id: body.id || randomUUID(),
      action: body.action,
      ...body,
    };
    if (!request.action) {
      sendJson(res, 400, { ok: false, error: "action required" });
      return;
    }
    const result = await callBridge(request);
    sendJson(res, 200, result);
  } catch (err) {
    sendJson(res, 500, {
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

/**
 * SSE thought stream — polls local life_thoughts_list.
 */
async function handleStream(req, res) {
  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
    "Access-Control-Allow-Origin": "*",
  });
  res.write(": connected\n\n");

  let since = new URL(req.url || "/", `http://${req.headers.host}`).searchParams.get(
    "since",
  );
  let closed = false;
  req.on("close", () => {
    closed = true;
  });

  const seen = new Set();

  async function tick() {
    if (closed) return;
    try {
      const result = await callBridge({
        id: randomUUID(),
        action: "life_thoughts_list",
        since: since || undefined,
        limit: 40,
      });
      const thoughts = (result && result.thoughts) || [];
      for (const t of thoughts) {
        const id = t.id || `${t.created_at}:${t.summary}`;
        if (seen.has(id)) continue;
        seen.add(id);
        res.write(`event: thought\ndata: ${JSON.stringify(t)}\n\n`);
        if (t.created_at && (!since || t.created_at > since)) {
          since = t.created_at;
        }
      }
      // Cap seen set
      if (seen.size > 500) {
        const arr = [...seen];
        arr.slice(0, arr.length - 200).forEach((k) => seen.delete(k));
      }
    } catch (err) {
      res.write(
        `event: error\ndata: ${JSON.stringify({ message: String(err.message || err) })}\n\n`,
      );
    }
    res.write(": heartbeat\n\n");
  }

  await tick();
  const interval = setInterval(() => {
    if (closed) {
      clearInterval(interval);
      return;
    }
    tick();
  }, 2000);
}

const server = http.createServer(async (req, res) => {
  const method = req.method || "GET";
  const url = (req.url || "/").split("?")[0];

  if (method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  if (method === "POST" && url === "/api/bridge") {
    await handleBridge(req, res);
    return;
  }

  if (method === "GET" && url === "/api/stream") {
    await handleStream(req, res);
    return;
  }

  if (method === "GET" && url === "/api/health") {
    sendJson(res, 200, { ok: true, service: "mission-deck", port: PORT });
    return;
  }

  if (method === "GET") {
    serveStatic(req, res);
    return;
  }

  res.writeHead(405);
  res.end("Method not allowed");
});

server.listen(PORT, HOST, () => {
  console.log(
    `Mission Deck ${DEV ? "(API-only --dev)" : ""} → http://${HOST === "0.0.0.0" ? "localhost" : HOST}:${PORT}`,
  );
  console.log(`Bridge python: ${PYTHON} (cwd ${REPO_ROOT})`);
});
