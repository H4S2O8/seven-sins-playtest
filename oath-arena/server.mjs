import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const root = path.dirname(fileURLToPath(import.meta.url));
http
  .createServer((req, res) => {
    let name = decodeURIComponent(
      new URL(req.url, "http://localhost").pathname,
    );
    if (name.endsWith("/")) name += "index.html";
    const f = path.resolve(root, "." + name);
    if (!f.startsWith(root + path.sep)) {
      res.writeHead(403).end();
      return;
    }
    fs.readFile(f, (e, b) => {
      if (e) {
        res.writeHead(404).end("Not found");
        return;
      }
      res.setHeader(
        "Content-Type",
        {
          html: "text/html; charset=utf-8",
          js: "text/javascript; charset=utf-8",
          css: "text/css; charset=utf-8",
          json: "application/json",
          svg: "image/svg+xml",
          png: "image/png",
        }[f.split(".").pop()] || "application/octet-stream",
      );
      res.setHeader("Cache-Control", "no-store");
      res.end(b);
    });
  })
  .listen(8937, "127.0.0.1", () => console.log("http://127.0.0.1:8937"));
