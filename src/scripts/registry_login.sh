#!/bin/bash

set -euo pipefail
# A job can turn xtrace on for every step (SHELLOPTS, or set -x in $BASH_ENV), and it would print the password.
set +o xtrace

# Prepare orb parameters
PASSWORD=${!PARAM_PASSWORD:-}
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REGISTRY=$(printf '%s' "${PARAM_REGISTRY}" | circleci env subst)
USERNAME=${!PARAM_USERNAME:-}

# Cleanup makes a best effort to destroy all secrets.
cleanup_secrets() {
    echo "Cleaning up secrets..."
    unset PASSWORD
    unset PARAM_PASSWORD
    unset USERNAME
    unset PARAM_USERNAME
    echo "Secrets destroyed."
}
trap cleanup_secrets EXIT

# Print parameters for debugging purposes
echo "Running Helm registry login command..."
echo "  PLAIN_HTTP: ${PLAIN_HTTP}"
echo "  REGISTRY: ${REGISTRY}"

# Optional flags
LOGIN_FLAGS=()
if [[ "${PLAIN_HTTP}" == "1" || "${PLAIN_HTTP}" == "true" ]]; then
    LOGIN_FLAGS+=(--plain-http)
fi

# Login to the registry. printf, not echo: echo would take a password of -n or
# -e as its own option. LOGIN_FLAGS is empty without plain_http, and bash
# before 4.4 treats an empty array as unset under set -u, so it is expanded
# only when it has elements.
printf '%s\n' "${PASSWORD}" |
    helm registry login --debug ${LOGIN_FLAGS[@]+"${LOGIN_FLAGS[@]}"} "${REGISTRY}" -u "${USERNAME}" --password-stdin
