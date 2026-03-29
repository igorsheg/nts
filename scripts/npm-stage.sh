#!/usr/bin/env bash
set -euo pipefail

# Generate all npm packages from a single source of truth.
# Usage: ./scripts/npm-stage.sh [version]
# Binaries must exist in dist/ (from `make cross` or CI artifacts).

VERSION="${1:-0.4.0}"
SCOPE="@igorsheg"
NAME="nts"
REPO="https://github.com/igorsheg/nts"
DESC="Note to self — quick markdown notes from your terminal"
LICENSE="MIT"
KEYWORDS='["cli", "notes", "markdown", "terminal"]'

PLATFORMS=(
  "darwin:arm64:aarch64-macos"
  "darwin:x64:x86_64-macos"
  "linux:arm64:aarch64-linux"
  "linux:x64:x86_64-linux"
)

DIST_DIR="dist"
NPM_DIR="npm"
rm -rf "$NPM_DIR"

# --- platform packages ---
OPTIONAL_DEPS=""
for entry in "${PLATFORMS[@]}"; do
  IFS=: read -r os cpu zig_target <<< "$entry"
  pkg="${NAME}-${os}-${cpu}"
  fqn="${SCOPE}/${pkg}"
  dir="${NPM_DIR}/${pkg}"

  mkdir -p "${dir}/bin"

  # copy binary if it exists (CI provides them)
  bin_src="${DIST_DIR}/nts-${os}-${cpu}"
  if [[ -f "$bin_src" ]]; then
    cp "$bin_src" "${dir}/bin/nts"
    chmod +x "${dir}/bin/nts"
  fi

  cat > "${dir}/package.json" <<EOF
{
  "name": "${fqn}",
  "version": "${VERSION}",
  "description": "${NAME} binary for ${os} ${cpu}",
  "license": "${LICENSE}",
  "repository": { "type": "git", "url": "${REPO}" },
  "os": ["${os}"],
  "cpu": ["${cpu}"],
  "files": ["bin/nts"]
}
EOF

  if [[ -n "$OPTIONAL_DEPS" ]]; then
    OPTIONAL_DEPS="${OPTIONAL_DEPS},"
  fi
  OPTIONAL_DEPS="${OPTIONAL_DEPS}
    \"${fqn}\": \"${VERSION}\""
done

# --- root package ---
ROOT_DIR="${NPM_DIR}/${NAME}"
mkdir -p "$ROOT_DIR"

cat > "${ROOT_DIR}/package.json" <<EOF
{
  "name": "${SCOPE}/${NAME}",
  "version": "${VERSION}",
  "description": "${DESC}",
  "license": "${LICENSE}",
  "repository": { "type": "git", "url": "${REPO}" },
  "keywords": ${KEYWORDS},
  "bin": { "${NAME}": "index.js" },
  "optionalDependencies": {${OPTIONAL_DEPS}
  }
}
EOF

cat > "${ROOT_DIR}/index.js" <<'SCRIPT'
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
SCRIPT

chmod +x "${ROOT_DIR}/index.js"

echo "staged ${VERSION}:"
find "$NPM_DIR" -name package.json | sort | while read -r f; do
  echo "  $f"
done
