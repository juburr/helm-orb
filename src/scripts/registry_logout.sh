#!/bin/bash

set -euo pipefail

# Prepare orb parameters
REGISTRY=$(printf '%s' "${PARAM_REGISTRY}" | circleci env subst)

# Print parameters for debugging purposes
echo "Running Helm registry logout command..."
echo "  REGISTRY: ${REGISTRY}"

# Logout of the registry
helm registry logout --debug "${REGISTRY}"
