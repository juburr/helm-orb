#!/bin/bash

# Convenience script, not used by directly by the production orb, but
# for development purposes when adding SHA-512 checksums to the lookup
# table in install.sh. Prints one table entry per architecture.

set -e
set +o history

# Fetch CLI arguments
# Can also be set as environment variables.
while getopts :v:a: flag
do
    case "${flag}" in
        v) VERSION=${OPTARG};;
        a) ARCHITECTURES=${OPTARG};;
        *) echo "Invalid option: -${OPTARG}" >&2; exit 1;;
    esac
done

# Default to every architecture that install.sh supports.
ARCHITECTURES=${ARCHITECTURES:-"amd64 arm64"}

# Validate input arguments
if [[ -z "${VERSION}" ]]; then
  echo "Must specify a version number."
  echo "Usage: $0 -v 1.0.0 [-a amd64|arm64]"
  echo "Alternatively: VERSION=1.0.0 $0"
  exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT
cd "${WORK_DIR}"

# Download each archive, confirm it matches the SHA-256 that Helm publishes next to it,
# then get the SHA-512 checksum of the helm binary inside. Suppress download output for
# readability; this is dev script, so simply re-enable output if you need to debug anything.
for ARCH in ${ARCHITECTURES}; do
    TARBALL="helm-v${VERSION}-linux-${ARCH}.tar.gz"
    wget "https://get.helm.sh/${TARBALL}" -O "${TARBALL}" -q
    # The bare-hash .sha256 file is published for every Helm 3 and 4 release (.sha256sum is not).
    PUBLISHED_SHA256=$(wget "https://get.helm.sh/${TARBALL}.sha256" -O - -q)
    echo "${PUBLISHED_SHA256}  ${TARBALL}" | sha256sum --check --quiet >&2
    tar -xzf "${TARBALL}" "linux-${ARCH}/helm" --strip-components 1
    CHECKSUM=$(sha512sum helm | awk '{ print $1 }')
    echo "[\"${VERSION}/${ARCH}\"]=\"${CHECKSUM}\""
    rm helm "${TARBALL}"
done
