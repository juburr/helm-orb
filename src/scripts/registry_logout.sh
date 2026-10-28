#!/bin/bash

set -euo pipefail

# subst VALUE: expands environment variables in VALUE with the CircleCI CLI,
# which reads it on stdin. Without the CLI, as in GitHub Actions or a local
# run, the value is used as it is.
subst() {
    if command -v circleci > /dev/null 2>&1; then
        printf '%s' "$1" | circleci env subst
    else
        printf '%s\n' "$1"
    fi
}

# Prepare orb parameters
REGISTRY=$(subst "${PARAM_REGISTRY}")

# Print parameters for debugging purposes
echo "Running Helm registry logout command..."
echo "  REGISTRY: ${REGISTRY}"

# Logout of the registry
helm registry logout --debug "${REGISTRY}"
