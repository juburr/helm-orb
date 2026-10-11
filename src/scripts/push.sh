#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART=$(circleci env subst "${PARAM_CHART}")
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REGISTRY=$(circleci env subst "${PARAM_REGISTRY}")

# Print parameters for debugging purposes
echo "Running Helm push command..."
echo "  CHART: ${CHART}"
echo "  PLAIN_HTTP: ${PLAIN_HTTP}"
echo "  REGISTRY: ${REGISTRY}"

# Optional flags
PUSH_FLAGS=()
if [[ "${PLAIN_HTTP}" == "1" || "${PLAIN_HTTP}" == "true" ]]; then
    PUSH_FLAGS+=(--plain-http)
fi

# Upload the Helm chart to a registry
helm push --debug "${PUSH_FLAGS[@]}" "${CHART}" "${REGISTRY}"
