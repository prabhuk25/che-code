#!/usr/bin/env bash
#
# Copyright (c) 2026 Red Hat, Inc.
# SPDX-License-Identifier: EPL-2.0
#
set -euo pipefail

PHASE="${1:-all}"
ARCH="$(uname -m)"

# Only run on unsupported architectures (skip on x86_64 / aarch64)
if [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "aarch64" ]; then
  echo "==> [ppc64le-compat] Architecture $ARCH is natively supported. Skipping compatibility patches."
  exit 0
fi

echo "==> [ppc64le-compat] Applying compatibility patches for $ARCH (phase: $PHASE)..."

if [ "$PHASE" = "pre-install" ] || [ "$PHASE" = "all" ]; then

  # 1. Patch build/lib/copilot.ts to skip unsupported platforms gracefully
  if [ -f "build/lib/copilot.ts" ]; then
    echo "==> [ppc64le-compat] Patching build/lib/copilot.ts..."
    sed -i 's/export function prepareBuiltInCopilotRipgrepShim(platform: string, arch: string, builtInCopilotExtensionDir: string, appNodeModulesDir: string): void {/export function prepareBuiltInCopilotRipgrepShim(platform: string, arch: string, builtInCopilotExtensionDir: string, appNodeModulesDir: string): void {\n\tif (!copilotPlatforms.includes(toCopilotPackagePlatformArch(platform, arch))) { return; }/' \
      build/lib/copilot.ts

    # Validation check: Ensure the patch was actually applied
    if ! grep -q "copilotPlatforms.includes" build/lib/copilot.ts; then
      echo "ERROR: Failed to patch build/lib/copilot.ts!" >&2
      exit 1
    fi
    echo "    [OK] build/lib/copilot.ts patched successfully."
  fi

  # 2. Disable @vscode/vsce-sign postinstall script in lockfiles
  echo "==> [ppc64le-compat] Disabling @vscode/vsce-sign in lockfiles..."
  for lock in build/package-lock.json extensions/copilot/package-lock.json package-lock.json; do
    if [ -f "$lock" ]; then
      sed -i '/@vscode\/vsce-sign/,/\}/s/"hasInstallScript": true/"hasInstallScript": false/' "$lock" || true
      echo "    [OK] Updated $lock"
    fi
  done

  # 3. Disable postinstall script in extensions/copilot/package.json
  if [ -f "extensions/copilot/package.json" ]; then
    echo "==> [ppc64le-compat] Disabling copilot extension postinstall..."
    sed -i 's/"postinstall": "tsx \.\/script\/postinstall\.ts"/"postinstall": "echo skipped"/' \
      extensions/copilot/package.json || true
    echo "    [OK] Updated extensions/copilot/package.json"
  fi

  # 4. Remove build_from_source from remote/.npmrc (prevents header download timeouts)
  if [ -f "remote/.npmrc" ]; then
    echo "==> [ppc64le-compat] Cleaning remote/.npmrc..."
    sed -i '/^build_from_source/d' remote/.npmrc || true
    echo "    [OK] Cleaned remote/.npmrc"
  fi

  # 5. Disable @parcel/watcher install script in remote/package-lock.json
  if [ -f "remote/package-lock.json" ]; then
    echo "==> [ppc64le-compat] Disabling parcel/watcher in remote/package-lock.json..."
    sed -i '0,/"hasInstallScript": true/s/"hasInstallScript": true/"hasInstallScript": false/' \
      remote/package-lock.json || true
    echo "    [OK] Updated remote/package-lock.json"
  fi

fi

if [ "$PHASE" = "post-install" ] || [ "$PHASE" = "all" ]; then

  # 6. Disable @vscode/vsce-sign in any extracted node_modules
  echo "==> [ppc64le-compat] Disabling vsce-sign in node_modules..."
  find . -path "*/node_modules/@vscode/vsce-sign/package.json" -exec \
    sed -i 's/"postinstall": "node \.\/src\/postinstall\.js"/"postinstall": "echo skipped"/' {} + 2>/dev/null || true

  # 7. Stub tsgo binary for unsupported architectures (no-op script)
  echo "==> [ppc64le-compat] Stubbing tsgo binaries..."
  find . -path "*/node_modules/.bin/tsgo" 2>/dev/null | while read -r f; do
    printf '#!/bin/sh\nexit 0\n' > "$f"
    chmod +x "$f"
    echo "    [OK] Stubbed tsgo at $f"
  done

fi

echo "==> [ppc64le-compat] All compatibility tasks finished successfully."
