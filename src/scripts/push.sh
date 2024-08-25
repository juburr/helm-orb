#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART=$(circleci env subst "${PARAM_CHART}")
REGISTRY=$(circleci env subst "${PARAM_REGISTRY}")

# Print parameters for debugging purposes
echo "Running Helm push command..."
echo "  CHART: ${CHART}"
echo "  REGISTRY: ${REGISTRY}"

# Upload the Helm chart to a registry
helm push --debug "${CHART}" "${REGISTRY}"
