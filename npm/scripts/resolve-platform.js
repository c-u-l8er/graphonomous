"use strict";

/**
 * Resolve Node.js runtime platform/architecture into Graphonomous binary artifact metadata.
 *
 * Supported targets:
 * - darwin-x64
 * - darwin-arm64
 * - linux-x64
 * - linux-arm64
 */

const PLATFORM_MAP = {
  darwin: "darwin",
  linux: "linux"
};

const ARCH_MAP = {
  x64: "x64",
  arm64: "arm64"
};

function normalizeVersion(version) {
  if (!version || typeof version !== "string") {
    throw new Error("A package version string is required.");
  }

  return version.startsWith("v") ? version.slice(1) : version;
}

function resolvePlatform(opts = {}) {
  const rawPlatform = opts.platform || process.platform;
  const rawArch = opts.arch || process.arch;
  const version = opts.version ? normalizeVersion(opts.version) : null;

  const platform = PLATFORM_MAP[rawPlatform];
  const arch = ARCH_MAP[rawArch];

  if (!platform) {
    throw new Error(
      `Unsupported platform "${rawPlatform}". Supported platforms: ${Object.keys(PLATFORM_MAP).join(", ")}.`
    );
  }

  if (!arch) {
    throw new Error(
      `Unsupported architecture "${rawArch}". Supported architectures: ${Object.keys(ARCH_MAP).join(", ")}.`
    );
  }

  const target = `${platform}-${arch}`;

  const result = {
    platform,
    arch,
    target,
    exeName: platform === "windows" ? "graphonomous.exe" : "graphonomous",
    archiveExt: "tar.gz"
  };

  if (version) {
    result.version = version;
    result.tag = `v${version}`;
    result.archiveName = `graphonomous-v${version}-${target}.${result.archiveExt}`;
  }

  return result;
}

function isSupportedPlatform(platform = process.platform, arch = process.arch) {
  return Boolean(PLATFORM_MAP[platform] && ARCH_MAP[arch]);
}

module.exports = {
  PLATFORM_MAP,
  ARCH_MAP,
  resolvePlatform,
  isSupportedPlatform
};
