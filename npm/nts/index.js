#!/usr/bin/env node

const { execFileSync } = require("child_process");
const path = require("path");
const os = require("os");

const PLATFORMS = {
  "darwin-arm64": "@igorsheg/nts-darwin-arm64",
  "darwin-x64": "@igorsheg/nts-darwin-x64",
  "linux-arm64": "@igorsheg/nts-linux-arm64",
  "linux-x64": "@igorsheg/nts-linux-x64",
};

const key = `${os.platform()}-${os.arch()}`;
const pkg = PLATFORMS[key];

if (!pkg) {
  console.error(`nts: unsupported platform ${key}`);
  process.exit(1);
}

let binPath;
try {
  binPath = path.join(require.resolve(`${pkg}/package.json`), "..", "bin", "nts");
} catch {
  console.error(
    `nts: platform package ${pkg} not installed.\n` +
    `Try reinstalling: npm install @igorsheg/nts`
  );
  process.exit(1);
}

try {
  execFileSync(binPath, process.argv.slice(2), { stdio: "inherit" });
} catch (e) {
  process.exit(e.status ?? 1);
}
