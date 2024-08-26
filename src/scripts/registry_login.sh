#!/bin/bash

set -e
set +o history

# Prepare orb parameters
PASSWORD=${!PARAM_PASSWORD_ENV}
REGISTRY=$(circleci env subst "${PARAM_REGISTRY}")
USERNAME=${!PARAM_USERNAME_ENV}

# Print parameters for debugging purposes
echo "Running Helm registry login command..."
echo "  REGISTRY: ${REGISTRY}"

# Login to the registry
echo "${PASSWORD}" | helm registry login --debug "${REGISTRY}" -u "${USERNAME}" --password-stdin
