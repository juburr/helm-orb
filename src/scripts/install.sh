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
    ["3.16.1"]="3caf691686547d299f5bd575b155cbc841909d5d1fb7661a1431a72a9e0868788874c71e97bdf8f32a805e266c2d1f94fc7b9be6fd783912697fdc53329cb169"
    ["3.16.0"]="910c1ab302ed2806f73ddea46d206a245daadd7da331b42ee90ca7baa40e3d187a4ba5fb906f69b89caad3f48c566643cbd8ab0996a0b8d3a3fb194183000af3"
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
    ["3.8.2"]="020c254e3b3c054d29c9a522d44540ec6eba1c9dc6fcc6f63aad81d05276f7f60bd217d0aa6c0911f95591d218bf3e4499af1cc1d3412827a24950351badf485"
    ["3.8.1"]="0727b8dbf153ef8f122d1784a37f0a16f53ead81f83b2791d14359c9f0550958ea924675abd0a546844f38b84bf8957695b2e390ed47851622223edab093d93e"
    ["3.8.0"]="f74575d5288ccf59a1883f658215c24c322e57ea96c8a9839638ab6cc3b8a1737b3d95651582830603779f1aefcd828448a16f3f78f139ddce2e85a85c3e1aa3"
    ["3.7.2"]="acc6e7e7d5b01be4789adb2dc6855e6d224621700a6ebd53ee52c46fe258344771f47b02d8853494d33422b137f84c3645107a085dabe3673202b041bc03c28f"
    ["3.7.1"]="108c9945bdc0a79b5315ff29eb6e0ebe968a25f276c5bf91393a555844227efde6cdd4974f115d89fa1992d22c3adde9d20d3773bdafa95a71251bc86fa0e8c6"
    ["3.7.0"]="96fd1be305ad7103e94286d9fbb84da89972cea548152c623a90b56b76a5237160e834725b82ef7cdd6d0f71ae7965b9ded1e1ca28e4e37c0c5d76c6879221eb"
    ["3.6.3"]="0354b1feb970b7a97a4e57dd6bb227a5009c045ff77519e9e85963f6108e9107b488f3b401fb456c80f9675002a2070bb793ff866da4b4611086466148b6963a"
    ["3.6.2"]="6a16ff92c7969a5f0a6d4a53ba0eaa081f631052f9fec84087550fa8ad1322b76b0961e1e0cccb54b5209672fe8eecdbf9064b7f33f20b8ca57eddc3e5ec16fb"
    ["3.6.1"]="55ef0c98a1c07f42f3dd3899a4e1fc93d68453b0ad8fce9fd25f560dc09d8cfec2e5114f78c5daa921ee0415c4aecb5fed7f61fe6aa0622ce2cb413911481b4a"
    ["3.6.0"]="b452c0071cd8dc4a796683d5b80fd57b1febcabe784fad2ff4c672809d3cc61c73f5bd46187008b234f1e383e94631ddebd13d3c547f3dea475453f68adb405c"
    ["3.5.4"]="a7aa2810507b012a1696e02f3bbb615cf09cc574cb27937197a3b860192069ad1659f504a51282ff6a93121dc932f77e4d96e6efa44525c2ba1b7b7d21aabb8b"
    ["3.5.3"]="1727b74fc1ec04476ee2068440faf019b858cd3f6956595137d42d35d42825cae2b3d0de0cb61ca625ed0371885ecbdc5571cfcdc029f454c395fa561932f929"
    ["3.5.2"]="e3aa1d2b8979ad69eee3e1c740b97729cb4a5857a667c16679d179426f6f967ef1d742a59217437650a422e2694d32653f32c76a85a1fb471d3980bf22d19f4f"
    ["3.5.1"]="e3c2f536abe5632852243bc4f3f8d31ea3db673b40c8dfd8ad610881b2270d5dc497c676dec7e9b0e0fd797e89e057356e3a447cc8ae1d2ac8e8d31afb079e00"
    ["3.5.0"]="c5a0abbd34bd65ffbf321f17393ccfbbb76d1c2d106bfcb738f711c2061293e937f56781c65443d91f9a63b48ffa9b73a199e5bf36f2ffe72df2bb2e3d20c788"
    ["3.4.2"]="d89093f1c463355b7280017c357a7d86825548a96d6b6772ae07fcc76a25474d02d3ba8f125514c49ff83383410863cd8b56702c5f9dcfa1f3f0d23ac1587fa1"
    ["3.4.1"]="dba79d7081858331d28655b15280d4b6575b120e82486d869c70ab6d662ddaa29e02fe0fa38f3a57e908e8b0be9e210247cb06cba36800c9689c63c4087e16d8"
    ["3.4.0"]="c8f5269553177dc5f310dc2c462bbab91edd38d8c11b35f7ab798dc3315606606edb5763f2df46ea39b919e54be4be85953c933a4adb5fc72ca214b918bc3bf1"
    ["3.3.4"]="2f5db203a6bdaa8ce4cdf075db0b981458359fe73f8c523c96d5cb16cfbf803ce53d08b5fda8bcb30f62ffa4836fb860b7cfc02244ce7d0ec463cb19dfbc80c3"
    ["3.3.3"]="516f0b9b98d0f72df3e702bb8cdd852c2ce807ae915f6d78469a4eed88829aa13be9a87e6c6bbd2514d28cbb4fc182c27d2d5d78766e5f901db39e2492685b48"
    ["3.3.2"]="f0364818a6b3fdeeb75027572c87702e67fa8190571559968cead2af53d0e4bd40e7d8764824de98ffc4e7749bf19b9cd2987a70cd5f8a4d3a2bd8e15fba136b"
    ["3.3.1"]="c3028af61303aeacdc31a12846be608b5115edb2e49543736647534b92d8a310df70e390b0c0f05e65ca23f9ca48f816c431d21b6d04dbd54185a9aee8d1106c"
    ["3.3.0"]="7bd61e82bf94505049e3a227a20c19b4a5a202740cc53da4bcf1615b8be76e516e090a73d5dbd64df39b413228df598d9018c3ecaf3cf5511dde2ceb064fc6f1"
    ["3.2.4"]="a578cf6600f740e497414a0c842d805cade34b0fd0bedd527bfa291e033f65c91ccbb707fec447c8e40a174a477efe2f4c2d0f7c265b70cdc2203d5f72b32695"
    ["3.2.3"]="37c27c394d547de988453b0099683b0f3ce7da0bc4fa55306cac2f760caf443287a941dc5e8592fb8f1aceedbc0ab063f5de3301f791e91580f0d704311be165"
    ["3.2.2"]="45573dfb90c757e2d93dff4a892936dab834a545e33aef194ec60236c70fe713c7db195fa685b2c4396e2d8b5a0e67de5e9b3b237b0bbc372b873b954a185d73"
    ["3.2.1"]="e4de25ca4720236ef2bb50be6ed57ec9779526e09cae4e9da5c0173c964c46475e8b4276bef91ccf3eb23f0d0edf8cd314d87c19bcb0099731d7984e1e9cdcc4"
    ["3.2.0"]="8e8da609f50757e542a1449b00f1a53e53653c961e0db6a3ac4f1caabc5653f2e0ad77a96553e0c6a670fe0a28c6b7ae2b7af78fb1af9a9632c10b6e17a07a2a"
    ["3.1.3"]="12ceb64adc95ba8066440b4214a2b2413355681cc5ad3090dcd27039bdebc3a9c0f8bdc615d52f2702f2eafd0cc34656316d5c1b0e9bec0e1a45ce688dbd6390"
    ["3.1.2"]="97b84740ca89732e2a3e610912c1e2a1d022c2470164562fc8094dfcf3163530f99e7a7353e8a638e7d9d3a36bf92578752cd6b2a106eefd9110d30ed464fc72"
    ["3.1.1"]="28523da84731d8d80777673b351c4baea0a33f816846d67d783496cc3eeee990ba0362cf4db822e886a9baa66a98b87cb5a24622eafefbb0334b5f64eaaa9282"
    ["3.1.0"]="b36697314fafc5f5cb090d87feba98d5cc4b8e08ffb0f375a15b8799f602f0e986428687655ac4b8d758d584e5d1aca03005d6deb9e3d9c691c4751da9af8d5e"
    ["3.0.3"]="fdfaec2192f2e4d401c67e10330186ee8f803264fb75ced01ba86c9f4190615191b6c3e03b8c6a1bd034671cafe7b155a767f13c106f46a0a653c9d7079e65e4"
    ["3.0.2"]="529bc0c9875db208e3b7eac67e66e7b73af8861e61f3bb1bfe4aa947089d00dfa4278fdd391da8a825e38cccbcb0960835022978a0fd55027a590662ae58f57e"
    ["3.0.1"]="a16cd36cf07be054bf8bad29dbe91f46e0fc1056c9adec51b47453c7fd063da1d8792ab1d0eef00c8cd94446c0f6c5de6052ae0acc3df905f015e069edd322d7"
    ["3.0.0"]="849568bbd075c9dc30812bf8ccc5a42c35917ac98b1a82d2909558b6c81e8c64c5293a856ee19a9c3eaf3be6a5309e42294f5e549b4a228508c7c747908fb7c4"
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
