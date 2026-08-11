#!/usr/bin/env bash
# post-create.sh — dev container provisioning for the template repository.
#
# Installs the tools a template contributor needs beyond the base image:
#   - jq         (used by the setup-* scripts and CI guards)
#   - shellcheck (same pinned version as ci.yml — keep the two in sync)
#
# gh ships via the github-cli dev container feature; git/curl come with
# the base image. This file serves the template repository only:
# scaffold-init.sh does not install .devcontainer/ into adopting repos.
set -euo pipefail

# Keep in sync with SHELLCHECK_VERSION / SHELLCHECK_SHA256 in
# .github/workflows/ci.yml (the x86_64 hash below is the same pin).
SHELLCHECK_VERSION="v0.11.0"
SHELLCHECK_SHA256_X86_64="8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198"
SHELLCHECK_SHA256_AARCH64="12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588"

sudo apt-get update -q
sudo apt-get install -y -q jq xz-utils

arch="$(uname -m)"
case "$arch" in
  x86_64)          sc_arch="x86_64";  sc_sha="$SHELLCHECK_SHA256_X86_64" ;;
  aarch64 | arm64) sc_arch="aarch64"; sc_sha="$SHELLCHECK_SHA256_AARCH64" ;;
  *)
    echo "post-create: unsupported architecture '$arch' — install shellcheck manually" >&2
    exit 1
    ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
curl -fsSLo "$tmpdir/shellcheck.tar.xz" \
  "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${sc_arch}.tar.xz"
echo "${sc_sha}  $tmpdir/shellcheck.tar.xz" | sha256sum -c -
tar -xJf "$tmpdir/shellcheck.tar.xz" -C "$tmpdir"
sudo install "$tmpdir/shellcheck-${SHELLCHECK_VERSION}/shellcheck" /usr/local/bin/shellcheck

echo
echo "post-create: environment ready"
git --version
gh --version | head -1
jq --version
shellcheck --version | sed -n 2p
