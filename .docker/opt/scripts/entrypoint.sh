#!/usr/bin/env bash
echo "Running entrypoint script..."
set -e
source /opt/scripts/env-secrets-expand.sh
source /opt/scripts/startup-commands.sh
exec "$@"
