#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART=$(circleci env subst "${PARAM_CHART}")
PASSWORD=${!PARAM_PASSWORD_ENV}
UPLOAD_PATH=$(circleci env subst "${PARAM_UPLOAD_PATH}")
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
echo "Running Helm raw push command..."
echo "  CHART: ${CHART}"
echo "  UPLOAD_PATH: ${UPLOAD_PATH}"

# Require HTTPS to be used
if [[ "${UPLOAD_PATH}" == https* ]]; then
    echo "The UPLOAD_PATH starts with 'https'. Proceeding..."
else
    echo "The push_raw command currently requires the use the HTTPS."
    echo "Credentials are included within request headers."
    exit 1
fi

# Upload the Helm chart to a raw repository
# Avoid verbose argument due to potential to leak headers; manually write out HTTP response code to debug instead.
curl -u "${USERNAME}:${PASSWORD}" "${UPLOAD_PATH}" --upload-file "${CHART}" -w "Response code: %{http_code}\n"
