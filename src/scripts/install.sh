#!/bin/bash

set -e

# Read in orb parameters
INSTALL_PATH=$(circleci env subst "${PARAM_INSTALL_PATH}")
VERIFY_CHECKSUMS="${PARAM_VERIFY_CHECKSUMS}"
VERSION=$(circleci env subst "${PARAM_VERSION}")

# Print command arguments for debugging purposes.
echo "Running Helm installer..."
echo "  INSTALL_PATH: ${INSTALL_PATH}"
echo "  VERIFY_CHECKSUMS: ${VERIFY_CHECKSUMS}"
echo "  VERSION: ${VERSION}"

# Lookup table of sha512 checksums for different versions of helm
declare -A sha512sums
sha512sums=(
    ["3.15.4"]="37a696e9629bd2d088e69130aeace2bc3380dfa5b0f52900346903f3ac6e9e13d47db279f173cd0a6bb8510c33cc1ef9de0fcc53d953079fdc6b5e53d3daf130"
    ["3.15.3"]="93db94da6e385b5b403aded651adc7dd3fcbbfa01d42e39c91f656be929d0bed2f6fc8f9b32a4e1492c0988f32dde82b7cae29eec0ca03543da1d05478e50402"
    ["3.15.2"]="3982086bb493f27fbd78172878945993f12af33ff1daee70c30512790176ee8c3d99a5c0367ae183ed5c47065c542d40aa1582ac907cc181ad86c248c8ff5e05"
    ["3.15.1"]="2bad6de17b687e8ccfcb95b6b435ef467f023f9c52ef129d3be306cd7a662d947dd925d2e52e4ea06869faf9f5ee363156e758d1af24c1f68692260ef58b9087"
    ["3.15.0"]="f79ffd4f7d387a7a4bf7982cc3a4fcd8d8be0f7734a6b65643fc972eac03f4aa3b905ee3ee6b04903ade7877532ead20737c3427d38ab23dcdc28a67fb2a997c"
    ["3.14.4"]="21a0a1db41c0ced37d29bb64a20af32f0795378cd9206161a64c3d2fdd3b9263f5b51b702eef4b62a7718ecfe605f069deb77897fab18740678559d40afb2c03"
    ["3.14.3"]="830d2758870c8b010826abb2a1c5fa81676df1531fce6df5489724e646d9a612a6508af6b0ba0a6b56ecee7fb50dfb6738c312ab494724cbe982652fd7b6ccfe"
    ["3.14.2"]="58da09644db664ae007a7e5f0fdf0b3a346def3326a4b7725a5d4251b88b7e11944a5bd18f1162882e6c5812016e27d18bfebad2290ba0dda85ce5eb5c1d3fe3"
    ["3.14.1"]="1293bee6e3b3205b35bd285fc0114ce8254de28922b8c4484f9baec747c9896b8efe082cf4fe2ea5dcf61d834d56afce3f87c67d9a087ab7bdc0c5838c285b14"
    ["3.14.0"]="f128e4f7ba44913247041813ede58361d8c29d35ea3054eba666d0ff6651f32e5389bc371c246ffa61f058de2e55bd344a6aad7d249a7cadc150ae3e7952f4db"
    ["3.13.3"]="fca98aa0a1c601d2bb7e006637d8a21c0172ccca1f9198292d23244b1df0ec515672b765d3de56046b4ccde04a6f44d11d7121a3f75846718301026cb56f38e7"
    ["3.13.2"]="d5ebe06bae205fa0c2f8dee472d09e4f6e441cbfe80f00274883610a1dde3338721982cbd3f61be94c2fb2bdf43a1aaa8fabc563094f667272a50b6f3a0ade42"
    ["3.13.1"]="174833971dc0a99a2e57ff2c3d7e306892375d987e13e61f796a3f716bfb6d6ca751e1fc0db0321a8a3dd613ea170339daf522640977aa7bfa90e07cb5a8f1ed"
    ["3.13.0"]="31c3c958399b424b30d20f2e935e62ac26b995b82d475c64850f5993f9a9b3ff6a606712bc8ce05d4eaecdc86b4b4de14f8fb8fcf4aab284774a6d8a4fca45d4"
    ["3.12.3"]="f8652c7f62b126b547c62f3355ebe9f77b7b2dd53af7f4ca84d4182023157fc2fad1a5f22e4ecf5dfc3b6a1838df823743132c02deb3a120c6c66eb9aae7e5ee"
    ["3.12.2"]="8037f7d98c7186ced0f41e18056717507ef66ff4df7171e9775e56338311a31a1290db8c2467f259a7c7d99d636b9360577273da50aa7c250a3a02d16a900857"
    ["3.12.1"]="b273d3dcac9012ee07e6e390d7a91fbc3848de1f2623edd8e2d414aa434de01df4472b29950e2556c78df221ab1bc08cee9d54ae91b033b512004bd0ee5c4730"
    ["3.12.0"]="fb8963b02c59aa10563db54a5f30999be308d23a4089eecece9f7c0a0afa03c3464cf3982c6db309985d2c87a974a305fce7e13ee1b2968807cc217c4c5a7846"
    ["3.11.3"]="16cb719e5a5a695721e4add23a88222502c84c466ec98d8b6bddad04ddb5f960b74cff116143f0b1029ca2093642656313e9d950496f3e15576bc17cacf2e47f"
    ["3.11.2"]="b29c145ac33d03c7513797afe4caf1ba7f5e9b0555cc2b18a0df0dffb3a20d8ffc90dc9713f11df8237a79a80f716ed6374a47b33484a66bfbae93a66a3cf23d"
    ["3.11.1"]="ded2f48c530a9a6b6cf863a83b8a22865958191e2b58e2379eef9d08b1ca307a90b944d25d27d53d1aaffd55aa24ca5ecae7c2e77313c2639af9c0ccf7b00c2c"
    ["3.11.0"]="76bfc6e3d3c41ec11b4c85d268d836994ea3a9db6be5e71cb9334520ff9e1463d6a3c9314fe334246a5bdf3629c67a56cd0cc60ae058bfb34946d1a06301360d"
    ["3.10.3"]="112c78fdeb5bab739f43c67126b422369fe3df3bbb0399682ac784451fd24801f6902da927ebcff86d8ad767be9ccfaaffca1b221975390df6a430f12c4d40db"
    ["3.10.2"]="3fce40674407cec966e329aa6dc93d1ca8fcd8dca7171d5b532a82ccae134174aaa54aa9e75056bd58f5a5a4739234494ff591fc2f46ba8558953a82cc93d4bf"
    ["3.10.1"]="56c89e4f0691ed9571a8a620ddba5d56ad6effe39a275fc88c942a7c97878fc2da6eba927f21a627bd704f91377c25c22d63864afbbea168cf628f532bc69e5d"
    ["3.10.0"]="b8e6689287958ad70d5e905b88c0d90d36ce0191fa75e58642bd0266b77e5f68e5b0fa2af06d41ce3f57b9b0e9f2bbd5d829a34d0a2bb06c57244012d2aa54ed"
    ["3.9.4"]="e5d97b0a9895e5dc86d74df330286450846b76b7218d6d84dfe810ef10d961123bc9e1b4c140377c7f1839bdc0d60563df262f6f778e81557320a6c596b4d1ed"
    ["3.9.3"]="4119dc520ca0aba424a7b3595ce8533e57138635c219841305b3d14f206a175e523804a246bc41b812cc8e88fb306d5db4278d0157dc419fa7839bc36a2c224b"
    ["3.9.2"]="908d704c1b0c0ad2b59e20245786c385f3997c4e25d526157511cef9a0febfb16851fb439af53ae0bf6a9e1ae97f96e5162a316bcc09d08f3ed4da15cd2f652f"
    ["3.9.1"]="580666e8c4cdcba473c8e425006951933fd497d90e28ee020911bc183a576765c42738d8eefc6f7e9d9983f16d81c58de0db3b2e79737abd1853a871c2d27b9e"
    ["3.9.0"]="12c8376c11d684276aeb37770f1efee4b46dda3d9f5f074e301980ba08e529204e2009ab8504ef6a5901594806f6f37a9cb0f5fd4f120d0ba6e727cb407a61b1"
    # TODO: Add checksums for old versions...
)

# Verfies that the SHA-512 checksum of a file matches what was in the lookup table
verify_checksum() {
    local file=$1
    local expected_checksum=$2

    actual_checksum=$(sha512sum "${file}" | awk '{ print $1 }')

    echo "Verifying checksum for ${file}..."
    echo "  Actual: ${actual_checksum}"
    echo "  Expected: ${expected_checksum}"

    if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
        echo "ERROR: Checksum verification failed!"
        exit 1
    fi

    echo "Checksum verification passed!"
}

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
# through cache or re-downloaded. First verify its integrity.
if [[ "${VERIFY_CHECKSUMS}" != "false" ]]; then
    EXPECTED_CHECKSUM=${sha512sums[${VERSION}]}
    if [[ -n "${EXPECTED_CHECKSUM}" ]]; then
        # If the version is in the table, verify the checksum
        verify_checksum "helm" "${EXPECTED_CHECKSUM}"
    else
        # If the version is not in the table, this means that a new version of Cosign
        # was released but this orb hasn't been updated yet to include its checksum in
        # the lookup table. Allow developers to configure if they want this to result in
        # a hard error, via "strict mode" (recommended), or to allow execution for versions
        # not directly specified in the above lookup table.
        if [[ "${VERIFY_CHECKSUMS}" == "known_versions" ]]; then
            echo "WARN: No checksum available for version ${VERSION}, but strict mode is not enabled."
            echo "WARN: Either upgrade this orb, submit a PR with the new checksum."
            echo "WARN: Skipping checksum verification..."
        else
            echo "ERROR: No checksum available for version ${VERSION} and strict mode is enabled."
            echo "ERROR: Either upgrade this orb, submit a PR with the new checksum, or set 'verify_checksums' to 'known_versions'."
            exit 1
        fi
    fi
else
    echo "WARN: Checksum validation is disabled. This is not recommended. Skipping..."
fi

# After verifying integrity, install it by moving it to
# an appropriate bin directory and marking it as executable.
mv helm "${INSTALL_PATH}/helm"
chmod +x "${INSTALL_PATH}/helm"
