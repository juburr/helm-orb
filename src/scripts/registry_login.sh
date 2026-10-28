#!/bin/bash

set -euo pipefail
# A job can turn xtrace on for every step (SHELLOPTS, or set -x in $BASH_ENV), and it would print the password.
set +o xtrace

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

# Fails unless parameter $1's value, $2, is an environment variable name.
# CircleCI checks env_var_name parameters before the step runs; the GitHub
# Action passes any string. The value isn't printed, in case a secret was
# passed instead of a name.
require_var_name() {
    if [[ ! "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        echo "ERROR: The $1 parameter must be the name of an environment variable." >&2
        exit 1
    fi
}
require_var_name username "${PARAM_USERNAME}"
require_var_name password "${PARAM_PASSWORD}"

# Prepare orb parameters
PASSWORD=${!PARAM_PASSWORD:-}
PLAIN_HTTP="${PARAM_PLAIN_HTTP}"
REGISTRY=$(subst "${PARAM_REGISTRY}")
USERNAME=${!PARAM_USERNAME:-}

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
if [[ "${PLAIN_HTTP}" == true ]]; then
    LOGIN_FLAGS+=(--plain-http)
fi

# Login to the registry. printf, not echo: echo would take a password of -n or
# -e as its own option. LOGIN_FLAGS is empty without plain_http, and bash
# before 4.4 treats an empty array as unset under set -u, so it is expanded
# only when it has elements.
printf '%s\n' "${PASSWORD}" |
    helm registry login --debug ${LOGIN_FLAGS[@]+"${LOGIN_FLAGS[@]}"} "${REGISTRY}" -u "${USERNAME}" --password-stdin
