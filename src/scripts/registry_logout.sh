#!/bin/bash

set -e
set +o history

# Prepare orb parameters
REGISTRY=$(printf '%s' "${PARAM_REGISTRY}" | circleci env subst)

# Print parameters for debugging purposes
echo "Running Helm registry lgout command..."
echo "  REGISTRY: ${REGISTRY}"

# Logout of the registry
helm registry logout --debug "${REGISTRY}"
