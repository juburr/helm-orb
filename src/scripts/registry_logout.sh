#!/bin/bash

set -e
set +o history

# Prepare orb parameters
REGISTRY=$(circleci env subst "${PARAM_REGISTRY}")

# Print parameters for debugging purposes
echo "Running Helm registry lgout command..."
echo "  REGISTRY: ${REGISTRY}"

# Logout of the registry
helm registry logout --debug "${REGISTRY}"
