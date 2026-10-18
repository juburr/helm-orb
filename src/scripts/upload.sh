#!/bin/bash

set -e
set +o history

# Prepare orb parameters. PARAM_USERNAME and PARAM_PASSWORD hold the names of
# the environment variables that hold the credentials, not the credentials.
CHART=$(printf '%s' "${PARAM_CHART}" | circleci env subst)
URL=$(printf '%s' "${PARAM_URL}" | circleci env subst)
USERNAME_VAR="${PARAM_USERNAME}"
PASSWORD_VAR="${PARAM_PASSWORD}"

# Fails unless parameter $1's value, $2, is an environment variable name. The
# value isn't printed, in case a secret was passed instead of a name.
require_var_name() {
    if [[ ! "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "The $1 parameter must be the name of an environment variable."
        exit 1
    fi
}
require_var_name username "${USERNAME_VAR}"
require_var_name password "${PASSWORD_VAR}"
USERNAME="${!USERNAME_VAR}"
PASSWORD="${!PASSWORD_VAR}"

RESPONSE_FILE=$(mktemp)

# Cleanup makes a best effort to destroy all secrets.
cleanup_secrets() {
    echo "Cleaning up secrets..."
    unset PASSWORD
    unset PARAM_PASSWORD
    unset USERNAME
    unset PARAM_USERNAME
    rm -f "${RESPONSE_FILE}"
    echo "Secrets destroyed."
}
trap cleanup_secrets EXIT

# Print parameters for debugging purposes
echo "Running Helm chart upload command..."
echo "  CHART: ${CHART}"
echo "  URL: ${URL}"
echo "  USERNAME: \$${USERNAME_VAR}"
echo "  PASSWORD: \$${PASSWORD_VAR}"

# Require HTTPS to be used. Match the full scheme: curl sends a URL without one over
# plain HTTP, so a bare "https" prefix would also accept a host like "https-nexus.example".
if [[ "${URL}" == https://* ]]; then
    echo "The URL starts with 'https://'. Proceeding..."
else
    echo "The upload command requires a url starting with 'https://'."
    echo "Credentials are included within request headers."
    exit 1
fi

if [[ ! -f "${CHART}" ]]; then
    echo "The chart '${CHART}' is not a file."
    exit 1
fi

if [[ -z "${USERNAME}" ]]; then
    echo "\$${USERNAME_VAR}, named by the username parameter, is unset or empty."
    exit 1
fi
if [[ -z "${PASSWORD}" ]]; then
    echo "\$${PASSWORD_VAR}, named by the password parameter, is unset or empty."
    exit 1
fi

# Quotes a value for a curl config file, where backslash escapes are recognized
# inside double quotes.
curl_config_quote() {
    local value=$1
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\t'/\\t}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    printf '"%s"' "${value}"
}

# Upload the Helm chart. The credentials reach curl in a config file read from
# stdin (--config -), rather than as arguments that other processes could see.
# printf is a shell builtin, so they never appear on a command line.
# Avoid verbose argument due to potential to leak headers; manually write out HTTP response code to debug instead.
CURL_RC=0
CURL_OUTPUT=$(printf 'user = %s\n' "$(curl_config_quote "${USERNAME}:${PASSWORD}")" \
    | curl --config - --silent --show-error --upload-file "${CHART}" --output "${RESPONSE_FILE}" \
        --write-out '%{http_code} %{url_effective}' "${URL}") || CURL_RC=$?
if [[ "${CURL_RC}" -ne 0 ]]; then
    echo "The upload failed: curl exited with code ${CURL_RC}."
    exit 1
fi

HTTP_CODE="${CURL_OUTPUT%% *}"
echo "Response code: ${HTTP_CODE}"
if [[ ! "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
    echo "The upload failed: the server responded with HTTP ${HTTP_CODE}."
    if [[ -s "${RESPONSE_FILE}" ]]; then
        echo "Response body (up to 4096 bytes):"
        head -c 4096 "${RESPONSE_FILE}"
        echo
    fi
    exit 1
fi
echo "Uploaded ${CHART} to ${CURL_OUTPUT#* }."
