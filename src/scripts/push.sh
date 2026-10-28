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
CHART=$(subst "${PARAM_CHART}")
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REMOTE=$(subst "${PARAM_REMOTE}")

# CircleCI checks the command's boolean before the step runs, and passes it as
# 1 or 0; the GitHub Action passes any string, and true or false.
case "${PLAIN_HTTP}" in
    1 | true) PLAIN_HTTP=true ;;
    0 | false) PLAIN_HTTP=false ;;
    *)
        echo "ERROR: plain_http must be true or false, not '${PLAIN_HTTP}'." >&2
        exit 1
        ;;
esac

# Print parameters for debugging purposes
echo "Running Helm push command..."
echo "  CHART: ${CHART}"
echo "  PLAIN_HTTP: ${PLAIN_HTTP}"
echo "  REMOTE: ${REMOTE}"

# Optional flags
PUSH_FLAGS=()
if [[ "${PLAIN_HTTP}" == true ]]; then
    PUSH_FLAGS+=(--plain-http)
fi

# Upload the Helm chart to a registry. PUSH_FLAGS is empty without plain_http,
# and bash before 4.4 treats an empty array as unset under set -u, so it is
# expanded only when it has elements.
helm push --debug ${PUSH_FLAGS[@]+"${PUSH_FLAGS[@]}"} "${CHART}" "${REMOTE}"
