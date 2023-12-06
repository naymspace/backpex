#!/usr/bin/env bash
echo "Running startup commands..."
for command in "${!STARTUP_COMMAND@}"; do
    printf 'Running %s: %s\n' "$command" "${!command}"
    eval ${!command}
done
