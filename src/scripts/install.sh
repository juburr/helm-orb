#!/bin/bash

set -e

# Read in orb parameters
INSTALL_PATH=$(circleci env subst "${PARAM_INSTALL_PATH}")
VERSION=$(circleci env subst "${PARAM_VERSION}")

# Check if the helm tar file was in the CircleCI cache.
# Cache restoration is handled in install.yml
if [[ -f helm.tar.gz ]]; then
    tar -xvzf helm.tar.gz linux-amd64/helm --strip-components 1
fi

# If there was no cache hit, go ahead and re-download the binary.
# Tar it up to save on cache space used.
if [[ ! -f helm ]]; then
    wget "https://get.helm.sh/helm-v${VERSION}-linux-amd64.tar.gz" -O helm.tar.gz
    tar -xvzf helm.tar.gz linux-amd64/helm --strip-components 1
fi

# A helm binary should exist at this point, regardless of whether it was obtained
# through cache or re-downloaded. Move it to an appropriate bin directory and mark it
# as executable.
mv helm "${INSTALL_PATH}/helm"
chmod +x "${INSTALL_PATH}/helm"