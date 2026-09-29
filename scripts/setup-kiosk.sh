#!/usr/bin/env bash
# Ansible owns the kiosk, including local assets and recovery services.
set -euo pipefail
cd "$(dirname "$0")/.."
exec ansible-playbook -i inventory kiosk.yml "$@"
