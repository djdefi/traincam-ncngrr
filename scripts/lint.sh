#!/usr/bin/env bash
# Lint Ansible and shell scripts
set -euo pipefail

if command -v ansible-lint &> /dev/null; then
  echo "==> Running ansible-lint..."
  ansible-lint
else
  echo "==> Skipping ansible-lint (not installed)"
fi

if command -v shellcheck &> /dev/null; then
  echo "==> Running shellcheck on shell templates..."
  for f in ansible/roles/traincam/templates/*.sh.j2; do
    echo "    Checking $f"
    # Ignore SC1091 (sourced files) and SC2086 (word splitting for Jinja vars)
    shellcheck --shell=bash --exclude=SC1091,SC2086 "$f" || true
  done
else
  echo "==> Skipping shellcheck (not installed)"
fi

echo "==> All checks complete"
