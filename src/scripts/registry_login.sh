#!/bin/bash

set -e
set +o history

# Prepare orb parameters
PASSWORD=${!PARAM_PASSWORD_ENV}
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REGISTRY=$(circleci env subst "${PARAM_REGISTRY}")
USERNAME=${!PARAM_USERNAME_ENV}

# Cleanup makes a best effort to destroy all secrets.
cleanup_secrets() {
    echo "Cleaning up secrets..."
    unset PASSWORD
    unset PARAM_PASSWORD_ENV
    unset USERNAME
    unset PARAM_USERNAME_ENV
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

# Login to the registry
echo "${PASSWORD}" | helm registry login --debug "${LOGIN_FLAGS[@]}" "${REGISTRY}" -u "${USERNAME}" --password-stdin
