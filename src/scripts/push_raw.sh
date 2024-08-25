#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART=$(circleci env subst "${PARAM_CHART}")
PASSWORD=${!PARAM_PASSWORD_ENV}
UPLOAD_PATH=$(circleci env subst "${PARAM_UPLOAD_PATH}")
USERNAME=${!PARAM_USERNAME_ENV}

# Print parameters for debugging purposes
echo "Running Helm raw push command..."
echo "  CHART: ${CHART}"
echo "  UPLOAD_PATH: ${UPLOAD_PATH}"

# Upload the Helm chart to a raw repository
curl -u "${USERNAME}:${PASSWORD}" "${UPLOAD_PATH}" --upload-file "${CHART}" -v
