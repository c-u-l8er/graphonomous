// npm postinstall script for Graphonomous.
// Downloads the platform-specific Graphonomous release binary into npm/vendor/<target>/.

"use strict";

const fs = require("fs");
const fsp = require("fs/promises");
const path = require("path");
const { resolvePlatform, isSupportedPlatform } = require("./resolve-platform");
const { downloadAndExtractReleaseAsset } = require("./download-release-asset");

const PACKAGE_ROOT = path.resolve(__dirname, "..");
const VENDOR_ROOT = path.join(PACKAGE_ROOT, "vendor");

function readPackageJson() {
  const pkgPath = path.join(PACKAGE_ROOT, "package.json");
  const raw = fs.readFileSync(pkgPath, "utf8");
  return JSON.parse(raw);
}

function parseGitHubRepoFromPackage(pkg) {
  const candidates = [
    pkg && pkg.repository && pkg.repository.url,
    pkg && pkg.homepage,
    pkg && pkg.bugs && pkg.bugs.url,
  ].filter(Boolean);

  for (const value of candidates) {
    const normalized = String(value);
    const match = normalized.match(
      /github\.com[:/](?<owner>[^/]+)\/(?<repo>[^/#?]+)/i,
    );

    if (!match || !match.groups) continue;

    const owner = match.groups.owner.trim();
    const repo = match.groups.repo.replace(/\.git$/i, "").trim();

    if (owner && repo) {
      return { owner, repo };
    }
  }

  return null;
}

function envFlag(name, defaultValue = false) {
  const raw = process.env[name];
  if (raw == null) return defaultValue;
  const normalized = String(raw).trim().toLowerCase();
  return ["1", "true", "yes", "on"].includes(normalized);
}

function getConfig(pkg) {
  const inferredRepo = parseGitHubRepoFromPackage(pkg) || {
    owner: "c-u-l8er",
    repo: "graphonomous",
  };

  const owner = process.env.GRAPHONOMOUS_GITHUB_OWNER || inferredRepo.owner;
  const repo = process.env.GRAPHONOMOUS_GITHUB_REPO || inferredRepo.repo;
  const version = process.env.GRAPHONOMOUS_VERSION || pkg.version;
  const tag =
    process.env.GRAPHONOMOUS_RELEASE_TAG || `v${version.replace(/^v/, "")}`;
  const token =
    process.env.GRAPHONOMOUS_GITHUB_TOKEN || process.env.GITHUB_TOKEN || null;
  const force = envFlag("GRAPHONOMOUS_FORCE_DOWNLOAD", false);
  const skip = envFlag("GRAPHONOMOUS_SKIP_DOWNLOAD", false);
  const timeoutMs = Number(
    process.env.GRAPHONOMOUS_DOWNLOAD_TIMEOUT_MS || 60_000,
  );
  const maxRedirects = Number(
    process.env.GRAPHONOMOUS_DOWNLOAD_MAX_REDIRECTS || 5,
  );
  const releaseBaseUrl = process.env.GRAPHONOMOUS_RELEASE_BASE_URL || null;

  return {
    owner,
    repo,
    version: version.replace(/^v/, ""),
    tag,
    token,
    force,
    skip,
    timeoutMs: Number.isFinite(timeoutMs) ? timeoutMs : 60_000,
    maxRedirects: Number.isFinite(maxRedirects) ? maxRedirects : 5,
    releaseBaseUrl,
  };
}

async function exists(filePath) {
  try {
    await fsp.access(filePath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function buildAssetName(version, target) {
  return `graphonomous-v${version}-${target}.tar.gz`;
}

function buildCustomAssetUrl(baseUrl, assetName) {
  const trimmed = String(baseUrl).replace(/\/+$/, "");
  return `${trimmed}/${assetName}`;
}

async function resolveInstalledCommandPath(targetDir, exeName) {
  const direct = path.join(targetDir, exeName);
  if (await exists(direct)) return direct;

  const otpDirect = path.join(targetDir, "bin", exeName);
  if (await exists(otpDirect)) return otpDirect;

  const entries = await fsp.readdir(targetDir, { withFileTypes: true });
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const nested = path.join(targetDir, entry.name, "bin", exeName);
    if (await exists(nested)) return nested;
  }

  throw new Error(
    `Could not locate installed Graphonomous command after extraction. ` +
      `Expected one of: ${direct}, ${otpDirect}, or <release>/bin/${exeName}.`,
  );
}

async function installCommandShim({ shimPath, sourceCommandPath }) {
  const shimDir = path.dirname(shimPath);
  const relativeTarget = path
    .relative(shimDir, sourceCommandPath)
    .replace(/\\/g, "/");

  const script = `#!/usr/bin/env sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$SCRIPT_DIR/${relativeTarget}" "$@"
`;

  await fsp.writeFile(shimPath, script, { encoding: "utf8", mode: 0o755 });
  await fsp.chmod(shimPath, 0o755);
}

async function writeInstallMetadata(targetDir, metadata) {
  const metadataPath = path.join(targetDir, ".install-metadata.json");
  await fsp.writeFile(metadataPath, JSON.stringify(metadata, null, 2), "utf8");
}

async function main() {
  const pkg = readPackageJson();
  const cfg = getConfig(pkg);

  if (cfg.skip) {
    console.log(
      "[graphonomous] postinstall skipped (GRAPHONOMOUS_SKIP_DOWNLOAD is set).",
    );
    return;
  }

  if (!isSupportedPlatform(process.platform, process.arch)) {
    console.warn(
      `[graphonomous] Unsupported platform for prebuilt binaries: ${process.platform}-${process.arch}.`,
    );
    console.warn(
      "[graphonomous] Install continues without binary. You can build Graphonomous manually from source.",
    );
    return;
  }

  const platformInfo = resolvePlatform({
    platform: process.platform,
    arch: process.arch,
    version: cfg.version,
  });

  const targetDir = path.join(VENDOR_ROOT, platformInfo.target);
  const binaryPath = path.join(targetDir, platformInfo.exeName);
  const assetName = buildAssetName(cfg.version, platformInfo.target);

  if (!cfg.force && (await exists(binaryPath))) {
    console.log(
      `[graphonomous] Binary already present at ${binaryPath}; skipping download.`,
    );
    return;
  }

  const useCustomBaseUrl = Boolean(cfg.releaseBaseUrl);
  const directUrl = useCustomBaseUrl
    ? buildCustomAssetUrl(cfg.releaseBaseUrl, assetName)
    : null;

  console.log(
    `[graphonomous] Installing Graphonomous binary for ${platformInfo.target} (version ${cfg.version})...`,
  );

  await downloadAndExtractReleaseAsset({
    url: directUrl || undefined,
    owner: cfg.owner,
    repo: cfg.repo,
    tag: cfg.tag,
    assetName,
    destinationDir: targetDir,
    stripComponents: 0,
    timeoutMs: cfg.timeoutMs,
    maxRedirects: cfg.maxRedirects,
    token: cfg.token,
    keepArchive: false,
    logger: console,
  });

  const installedCommandPath = await resolveInstalledCommandPath(
    targetDir,
    platformInfo.exeName,
  );

  if (installedCommandPath !== binaryPath) {
    await installCommandShim({
      shimPath: binaryPath,
      sourceCommandPath: installedCommandPath,
    });
  } else {
    await fsp.chmod(binaryPath, 0o755);
  }

  await writeInstallMetadata(targetDir, {
    packageName: pkg.name,
    packageVersion: pkg.version,
    resolvedVersion: cfg.version,
    tag: cfg.tag,
    target: platformInfo.target,
    binaryPath,
    installedCommandPath,
    installedAt: new Date().toISOString(),
    source: useCustomBaseUrl
      ? "custom_release_base_url"
      : `github:${cfg.owner}/${cfg.repo}`,
  });

  console.log(`[graphonomous] Installed binary: ${binaryPath}`);
  if (installedCommandPath !== binaryPath) {
    console.log(
      `[graphonomous] Installed command source: ${installedCommandPath}`,
    );
  }
}

main().catch((err) => {
  console.error("[graphonomous] postinstall failed.");
  console.error(err && err.stack ? err.stack : err);
  process.exitCode = 1;
});
