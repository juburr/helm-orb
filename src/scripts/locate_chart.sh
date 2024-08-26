#!/bin/bash

set -e
set +o history

# Prepare orb parameters
CHART_NAME=$(circleci env subst "${PARAM_CHART_NAME}")
CHART_VERSION=$(circleci env subst "${PARAM_CHART_VERSION}")
ENV_OUTPUT_PACKAGE=$(circleci env subst "${PARAM_ENV_OUTPUT_PACKAGE}")
SEARCH_DIRECTORY=$(circleci env subst "${PARAM_SEARCH_DIRECTORY}")

# Remove trailing slash from the directory path, if present.
SEARCH_DIRECTORY="${SEARCH_DIRECTORY%/}"

# Print parameters for debugging purposes
echo "Running Helm locate chart command..."
echo "  CHART_NAME: ${CHART_NAME}"
echo "  CHART_VERSION: ${CHART_VERSION}"
echo "  ENV_OUTPUT_PACKAGE: ${ENV_OUTPUT_PACKAGE}"
echo "  SEARCH_DIRECTORY: ${SEARCH_DIRECTORY}"

# Search for a matching Helm chart
OUTPUT_PATH=$(find "$(realpath "${SEARCH_DIRECTORY}")" -maxdepth 1 -type f \
    -name "*.tgz" -iname "*${CHART_NAME}*" -iname "*${CHART_VERSION}*" | head -n 1)

if [[ -z "${OUTPUT_PATH}" ]]; then
    echo "Unable to locate a Helm chart with the supplied parameters."
    exit 1
fi

if [[ -n "${ENV_OUTPUT_PACKAGE}" ]]; then
    export "${ENV_OUTPUT_PACKAGE}=${OUTPUT_PATH}"
    echo "export ${ENV_OUTPUT_PACKAGE}=${OUTPUT_PATH}" | tee -a "${BASH_ENV}"
fi
