#!/bin/bash
# scripts/check_assets.sh

set -e

# Check if there are any changes in priv/static/js directory
if ! git diff --exit-code priv/static/js/ > /dev/null 2>&1; then
  echo "❌ JS assets are not up to date in priv/static/js/"
  echo "Changed files:"
  git diff --name-only priv/static/js/
  echo ""
  echo "Please run 'mix assets.build' and commit the changes."
  exit 1
else
  echo "✅ JS assets are up to date"
fi
