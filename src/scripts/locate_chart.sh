#!/bin/bash

set -e
set +o history

# Prepare orb parameters. PACKAGE_ENV_VAR is a variable name, so it is not
# substituted.
CHART_NAME=$(printf '%s' "${PARAM_CHART_NAME}" | circleci env subst)
CHART_VERSION=$(printf '%s' "${PARAM_CHART_VERSION}" | circleci env subst)
PACKAGE_ENV_VAR="${PARAM_PACKAGE_ENV_VAR}"
SEARCH_DIR=$(printf '%s' "${PARAM_SEARCH_DIR}" | circleci env subst)

# Remove trailing slash from the directory path, if present.
SEARCH_DIR="${SEARCH_DIR%/}"

# Print parameters for debugging purposes
echo "Running Helm locate chart command..."
echo "  CHART_NAME: ${CHART_NAME}"
echo "  CHART_VERSION: ${CHART_VERSION}"
echo "  PACKAGE_ENV_VAR: ${PACKAGE_ENV_VAR}"
echo "  SEARCH_DIR: ${SEARCH_DIR}"

# The name is written into BASH_ENV, so it must be a plain variable name.
if [[ -n "${PACKAGE_ENV_VAR}" && ! "${PACKAGE_ENV_VAR}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "The package_env_var parameter must be the name of an environment variable, got '${PACKAGE_ENV_VAR}'."
    exit 1
fi

# Search for a matching Helm chart
OUTPUT_PATH=$(find "$(realpath "${SEARCH_DIR}")" -maxdepth 1 -type f \
    -name "*.tgz" -iname "*${CHART_NAME}*" -iname "*${CHART_VERSION}*" | head -n 1)

if [[ -z "${OUTPUT_PATH}" ]]; then
    echo "Unable to locate a Helm chart with the supplied parameters."
    exit 1
fi

if [[ -n "${PACKAGE_ENV_VAR}" ]]; then
    export "${PACKAGE_ENV_VAR}=${OUTPUT_PATH}"
    printf 'export %s=%q\n' "${PACKAGE_ENV_VAR}" "${OUTPUT_PATH}" | tee -a "${BASH_ENV}"
fi
