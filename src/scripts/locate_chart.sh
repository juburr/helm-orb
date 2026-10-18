#!/bin/bash

set -euo pipefail

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
    echo "ERROR: The package_env_var parameter must be the name of an environment variable, got '${PACKAGE_ENV_VAR}'." >&2
    exit 1
fi

# Search for a matching Helm chart. A find error, or find stopped early by
# head, leaves OUTPUT_PATH empty, which is reported below.
OUTPUT_PATH=$(find "$(realpath "${SEARCH_DIR}")" -maxdepth 1 -type f \
    -name "*.tgz" -iname "*${CHART_NAME}*" -iname "*${CHART_VERSION}*" | head -n 1) || true

if [[ -z "${OUTPUT_PATH}" ]]; then
    echo "ERROR: Unable to locate a Helm chart with the supplied parameters." >&2
    exit 1
fi

if [[ -n "${PACKAGE_ENV_VAR}" ]]; then
    if [[ -z "${BASH_ENV:-}" ]]; then
        echo "ERROR: BASH_ENV is unset, so ${PACKAGE_ENV_VAR} cannot be passed to later steps." >&2
        exit 1
    fi
    export "${PACKAGE_ENV_VAR}=${OUTPUT_PATH}"
    printf 'export %s=%q\n' "${PACKAGE_ENV_VAR}" "${OUTPUT_PATH}" | tee -a "${BASH_ENV}"
fi
