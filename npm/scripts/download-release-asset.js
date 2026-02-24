"use strict";

const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const os = require("os");
const http = require("http");
const https = require("https");
const { pipeline } = require("stream/promises");
const { spawn } = require("child_process");

const DEFAULT_TIMEOUT_MS = 60_000;
const DEFAULT_MAX_REDIRECTS = 5;

function normalizeTag(tag) {
  if (!tag || typeof tag !== "string") {
    throw new Error("A release tag is required (e.g. v0.1.0).");
  }
  return tag.startsWith("v") ? tag : `v${tag}`;
}

function buildGitHubReleaseAssetUrl({ owner, repo, tag, assetName }) {
  if (!owner) throw new Error("Missing GitHub owner.");
  if (!repo) throw new Error("Missing GitHub repo.");
  if (!assetName) throw new Error("Missing release asset name.");
  const normalizedTag = normalizeTag(tag);
  return `https://github.com/${owner}/${repo}/releases/download/${normalizedTag}/${assetName}`;
}

function ensureDir(dirPath) {
  return fsp.mkdir(dirPath, { recursive: true });
}

function streamRequestToFile(url, destinationPath, opts = {}) {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxRedirects = opts.maxRedirects ?? DEFAULT_MAX_REDIRECTS;
  const headers = { ...(opts.headers || {}) };

  return new Promise((resolve, reject) => {
    const visited = [];
    let settled = false;

    const onError = (err) => {
      if (!settled) {
        settled = true;
        reject(err);
      }
    };

    const requestUrl = (targetUrl, redirectsLeft) => {
      visited.push(targetUrl);

      if (redirectsLeft < 0) {
        onError(
          new Error(
            `Too many redirects while downloading release asset. Visited: ${visited.join(" -> ")}`
          )
        );
        return;
      }

      const parsed = new URL(targetUrl);
      const client = parsed.protocol === "http:" ? http : https;

      const req = client.get(
        targetUrl,
        {
          headers: {
            "user-agent": "graphonomous-npm-installer",
            ...headers
          },
          timeout: timeoutMs
        },
        async (res) => {
          const status = res.statusCode || 0;

          // Follow redirects
          if (status >= 300 && status < 400 && res.headers.location) {
            res.resume();
            const nextUrl = new URL(res.headers.location, targetUrl).toString();
            requestUrl(nextUrl, redirectsLeft - 1);
            return;
          }

          if (status < 200 || status >= 300) {
            const chunks = [];
            for await (const chunk of res) chunks.push(chunk);
            const body = Buffer.concat(chunks).toString("utf8");
            onError(
              new Error(
                `Failed downloading asset. HTTP ${status}. URL=${targetUrl}${
                  body ? `\nResponse: ${body.slice(0, 2000)}` : ""
                }`
              )
            );
            return;
          }

          try {
            await ensureDir(path.dirname(destinationPath));
            await pipeline(res, fs.createWriteStream(destinationPath));
            if (!settled) {
              settled = true;
              resolve({ finalUrl: targetUrl, destinationPath });
            }
          } catch (err) {
            onError(err);
          }
        }
      );

      req.on("timeout", () => {
        req.destroy(new Error(`Download timed out after ${timeoutMs}ms`));
      });

      req.on("error", onError);
    };

    requestUrl(url, maxRedirects);
  });
}

function runTarExtract({ archivePath, destinationDir, stripComponents = 0 }) {
  return new Promise((resolve, reject) => {
    const args = ["-xzf", archivePath, "-C", destinationDir];
    if (stripComponents > 0) {
      args.push(`--strip-components=${stripComponents}`);
    }

    const child = spawn("tar", args, {
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stderr = "";
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", (err) => {
      reject(
        new Error(
          `Failed to start tar process. Ensure 'tar' is available on this system.\n${err.message}`
        )
      );
    });

    child.on("close", (code) => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(
        new Error(
          `Failed to extract archive with tar (exit code ${code}).` +
            (stderr ? `\n${stderr.trim()}` : "")
        )
      );
    });
  });
}

async function fileExists(filePath) {
  try {
    await fsp.access(filePath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Downloads and extracts a release asset archive (tar.gz), then optionally marks
 * the expected executable as executable.
 *
 * Options:
 * - url: direct asset URL (optional if owner/repo/tag/assetName are provided)
 * - owner, repo, tag, assetName: used to build GitHub release URL
 * - destinationDir: where the archive should be extracted (required)
 * - archivePath: optional explicit temp archive path
 * - stripComponents: optional tar --strip-components value (default 0)
 * - executableName: optional executable to chmod +x after extraction
 * - timeoutMs: download timeout (default 60s)
 * - maxRedirects: max redirects (default 5)
 * - token: optional GitHub token for private assets
 * - keepArchive: keep downloaded archive on disk (default false)
 * - logger: optional logger object ({ info, warn, error })
 */
async function downloadAndExtractReleaseAsset(options = {}) {
  const logger = options.logger || console;
  const destinationDir = options.destinationDir;

  if (!destinationDir) {
    throw new Error("downloadAndExtractReleaseAsset: destinationDir is required.");
  }

  const stripComponents = Number.isInteger(options.stripComponents)
    ? options.stripComponents
    : 0;

  const assetUrl =
    options.url ||
    buildGitHubReleaseAssetUrl({
      owner: options.owner,
      repo: options.repo,
      tag: options.tag,
      assetName: options.assetName
    });

  const archivePath =
    options.archivePath ||
    path.join(
      os.tmpdir(),
      `graphonomous-${Date.now()}-${Math.random().toString(16).slice(2)}.tar.gz`
    );

  const headers = {};
  if (options.token && typeof options.token === "string") {
    headers.authorization = `Bearer ${options.token}`;
  }

  await ensureDir(destinationDir);

  logger.info?.(`Downloading Graphonomous release asset: ${assetUrl}`);
  await streamRequestToFile(assetUrl, archivePath, {
    timeoutMs: options.timeoutMs,
    maxRedirects: options.maxRedirects,
    headers
  });

  logger.info?.(`Extracting release asset into: ${destinationDir}`);
  await runTarExtract({
    archivePath,
    destinationDir,
    stripComponents
  });

  let executablePath = null;
  if (options.executableName) {
    executablePath = path.join(destinationDir, options.executableName);
    const exists = await fileExists(executablePath);
    if (!exists) {
      throw new Error(
        `Expected executable "${options.executableName}" not found after extraction at ${executablePath}.`
      );
    }

    // Ensure executable bit is present on unix-like systems
    await fsp.chmod(executablePath, 0o755);
  }

  if (!options.keepArchive) {
    try {
      await fsp.unlink(archivePath);
    } catch {
      // best-effort cleanup
    }
  }

  return {
    assetUrl,
    archivePath,
    destinationDir,
    executablePath
  };
}

module.exports = {
  normalizeTag,
  buildGitHubReleaseAssetUrl,
  streamRequestToFile,
  runTarExtract,
  downloadAndExtractReleaseAsset
};
