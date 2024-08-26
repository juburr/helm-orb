#!/bin/bash

set -e
set +o history

# Prepare orb parameters
PASSWORD=${!PARAM_PASSWORD_ENV}
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
echo "  REGISTRY: ${REGISTRY}"

# Login to the registry
echo "${PASSWORD}" | helm registry login --debug "${REGISTRY}" -u "${USERNAME}" --password-stdin
