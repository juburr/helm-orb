#!/bin/bash

set -e
set +o history

# Prepare orb parameters
APP_VERSION=$(circleci env subst "${PARAM_APP_VERSION}")
CHART_PATH=$(circleci env subst "${PARAM_CHART_PATH}")
CHART_VERSION=$(circleci env subst "${PARAM_CHART_VERSION}")
ENV_OUTPUT_PACKAGE=$(circleci env subst "${PARAM_ENV_OUTPUT_PACKAGE}")
OUTPUT_DIRECTORY=$(circleci env subst "${PARAM_OUTPUT_DIRECTORY}")

# Prepare parameters
# Remove trailing slash from the directory path, if present.
OUTPUT_DIRECTORY="${OUTPUT_DIRECTORY%/}"

# Print parameters for debugging purposes
echo "Running Helm package command..."
echo "  APP_VERSION: ${APP_VERSION}"
echo "  CHART_PATH: ${CHART_PATH}"
echo "  CHART_VERSION: ${CHART_VERSION}"
echo "  ENV_HELM_PACKAGE_FILENAME: ${ENV_HELM_PACKAGE_FILENAME}"
echo "  OUTPUT_DIRECTORY: ${OUTPUT_DIRECTORY}"

# Determine package name
PACKAGE_NAME=$(grep '^name:' "${CHART_PATH}/Chart.yaml" | awk '{print $2}')
echo "  PACKAGE_NAME: ${PACKAGE_NAME}"

# Create output directory, in case it doesn't exist yet
mkdir -p "${OUTPUT_DIRECTORY}"

# Package up the Helm chart
helm package \
    --app-version "${APP_VERSION}" \
    --destination "${OUTPUT_DIRECTORY}" \
    --debug \
    --version "${CHART_VERSION}" \
    "${CHART_PATH}"

# Extract and export filename for later use
if [[ -n "${ENV_OUTPUT_PACKAGE}" ]]; then
    OUTPUT_PATH=$(find "$(realpath "${OUTPUT_DIRECTORY}")" -maxdepth 1 -type f -name "*.tgz" \
        -iname "*${PACKAGE_NAME}*" -iname "*${CHART_VERSION}*" | head -n 1)
    export "${ENV_OUTPUT_PACKAGE}=${OUTPUT_PATH}"
    echo "export ${ENV_OUTPUT_PACKAGE}=${OUTPUT_PATH}" | tee -a "${BASH_ENV}"
fi
