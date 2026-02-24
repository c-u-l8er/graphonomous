#!/usr/bin/env node
"use strict";

/**
 * npm bin launcher for Graphonomous.
 *
 * This script resolves the installed platform-specific Graphonomous command in:
 *   npm/vendor/<platform>-<arch>/graphonomous/bin/graphonomous
 *
 * For OTP release assets, it executes the release command through:
 *   eval "Graphonomous.CLI.main(System.argv())"
 * and passes through all CLI arguments.
 */

const fs = require("fs");
const path = require("path");
const { spawn } = require("child_process");
const {
  resolvePlatform,
  isSupportedPlatform,
} = require("../scripts/resolve-platform");

const PACKAGE_ROOT = path.resolve(__dirname, "..");
const VENDOR_ROOT = path.join(PACKAGE_ROOT, "vendor");

function fail(message, code = 1) {
  console.error(`[graphonomous] ${message}`);
  process.exit(code);
}

function fileExists(p) {
  try {
    fs.accessSync(p, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function isExecutable(p) {
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function resolveBinaryPath() {
  const override = process.env.GRAPHONOMOUS_BINARY_PATH;
  if (override && override.trim()) {
    const candidate = path.resolve(override.trim());
    if (!fileExists(candidate)) {
      fail(
        `GRAPHONOMOUS_BINARY_PATH is set but file does not exist: ${candidate}`,
      );
    }
    return candidate;
  }

  if (!isSupportedPlatform(process.platform, process.arch)) {
    fail(
      `Unsupported platform "${process.platform}-${process.arch}". ` +
        `Supported targets: darwin/linux + x64/arm64.`,
    );
  }

  const info = resolvePlatform({
    platform: process.platform,
    arch: process.arch,
  });

  // Preferred layout for OTP release assets.
  const releaseCommandPath = path.join(
    VENDOR_ROOT,
    info.target,
    "graphonomous",
    "bin",
    info.exeName,
  );

  if (fileExists(releaseCommandPath)) {
    return releaseCommandPath;
  }

  // Backward-compatible fallback for single-file binary assets.
  const binaryPath = path.join(VENDOR_ROOT, info.target, info.exeName);
  if (fileExists(binaryPath)) {
    return binaryPath;
  }

  fail(
    `Installed Graphonomous command not found.\n` +
      `Checked:\n` +
      `  - ${releaseCommandPath}\n` +
      `  - ${binaryPath}\n` +
      `Try reinstalling package or rerunning install scripts:\n` +
      `  npm rebuild graphonomous\n` +
      `or\n` +
      `  npm i graphonomous@latest`,
  );
}

function run() {
  const binaryPath = resolveBinaryPath();

  // Best-effort chmod for unix-like systems if executable bit is missing.
  if (process.platform !== "win32" && !isExecutable(binaryPath)) {
    try {
      fs.chmodSync(binaryPath, 0o755);
    } catch {
      // ignore; spawn will report if it still cannot execute
    }
  }

  const args = process.argv.slice(2);
  const otpReleasePathPattern = new RegExp(
    `[\\\\/]graphonomous[\\\\/]bin[\\\\/]graphonomous$`,
  );
  const spawnArgs = otpReleasePathPattern.test(binaryPath)
    ? ["eval", "Graphonomous.CLI.main(System.argv())", ...args]
    : args;

  const child = spawn(binaryPath, spawnArgs, {
    stdio: "inherit",
    env: process.env,
  });

  child.on("error", (err) => {
    fail(`Failed to start binary at ${binaryPath}: ${err.message}`);
  });

  child.on("exit", (code, signal) => {
    if (signal) {
      // Mirror termination signal behavior.
      process.kill(process.pid, signal);
      return;
    }

    process.exit(typeof code === "number" ? code : 1);
  });

  // Forward common termination signals to child.
  const forward = (sig) => {
    if (!child.killed) {
      try {
        child.kill(sig);
      } catch {
        // no-op
      }
    }
  };

  process.on("SIGINT", () => forward("SIGINT"));
  process.on("SIGTERM", () => forward("SIGTERM"));
}

run();
