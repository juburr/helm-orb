#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART=$(printf '%s' "${PARAM_CHART}" | circleci env subst)
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REMOTE=$(printf '%s' "${PARAM_REMOTE}" | circleci env subst)

# Print parameters for debugging purposes
echo "Running Helm push command..."
echo "  CHART: ${CHART}"
echo "  PLAIN_HTTP: ${PLAIN_HTTP}"
echo "  REMOTE: ${REMOTE}"

# Optional flags
PUSH_FLAGS=()
if [[ "${PLAIN_HTTP}" == "1" || "${PLAIN_HTTP}" == "true" ]]; then
    PUSH_FLAGS+=(--plain-http)
fi

# Upload the Helm chart to a registry
helm push --debug "${PUSH_FLAGS[@]}" "${CHART}" "${REMOTE}"
