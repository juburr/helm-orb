#!/bin/bash

set -euo pipefail

# Prepare orb parameters. PACKAGE_ENV_VAR is a variable name, so it is not
# substituted.
APP_VERSION=$(printf '%s' "${PARAM_APP_VERSION}" | circleci env subst)
CHART_DIR=$(printf '%s' "${PARAM_CHART_DIR}" | circleci env subst)
CHART_VERSION=$(printf '%s' "${PARAM_CHART_VERSION}" | circleci env subst)
OUTPUT_DIR=$(printf '%s' "${PARAM_OUTPUT_DIR}" | circleci env subst)
PACKAGE_ENV_VAR="${PARAM_PACKAGE_ENV_VAR}"

# Prepare parameters
# Remove trailing slash from the directory path, if present.
OUTPUT_DIR="${OUTPUT_DIR%/}"

# Print parameters for debugging purposes
echo "Running Helm package command..."
echo "  APP_VERSION: ${APP_VERSION}"
echo "  CHART_DIR: ${CHART_DIR}"
echo "  CHART_VERSION: ${CHART_VERSION}"
echo "  OUTPUT_DIR: ${OUTPUT_DIR}"
echo "  PACKAGE_ENV_VAR: ${PACKAGE_ENV_VAR}"

# The name is written into BASH_ENV, so it must be a plain variable name.
if [[ -n "${PACKAGE_ENV_VAR}" && ! "${PACKAGE_ENV_VAR}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "ERROR: The package_env_var parameter must be the name of an environment variable, got '${PACKAGE_ENV_VAR}'." >&2
    exit 1
fi

# Determine package name. A missing name line is left for helm package to
# report.
PACKAGE_NAME=$({ grep '^name:' "${CHART_DIR}/Chart.yaml" || true; } | awk '{print $2}')
echo "  PACKAGE_NAME: ${PACKAGE_NAME}"

# Create output directory, in case it doesn't exist yet
mkdir -p "${OUTPUT_DIR}"

# Package up the Helm chart
helm package \
    --app-version "${APP_VERSION}" \
    --destination "${OUTPUT_DIR}" \
    --debug \
    --version "${CHART_VERSION}" \
    "${CHART_DIR}"

# Extract and export filename for later use
if [[ -n "${PACKAGE_ENV_VAR}" ]]; then
    if [[ -z "${BASH_ENV:-}" ]]; then
        echo "ERROR: BASH_ENV is unset, so ${PACKAGE_ENV_VAR} cannot be passed to later steps." >&2
        exit 1
    fi
    # head stops find early when several files match; that is not an error.
    OUTPUT_PATH=$(find "$(realpath "${OUTPUT_DIR}")" -maxdepth 1 -type f -name "*.tgz" \
        -iname "*${PACKAGE_NAME}*" -iname "*${CHART_VERSION}*" | head -n 1) || true
    export "${PACKAGE_ENV_VAR}=${OUTPUT_PATH}"
    printf 'export %s=%q\n' "${PACKAGE_ENV_VAR}" "${OUTPUT_PATH}" | tee -a "${BASH_ENV}"
fi
