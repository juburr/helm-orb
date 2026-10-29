#!/usr/bin/env bash
#
# Tests src/scripts/registry_login.sh against a stand-in helm that records its
# arguments and stdin:
#
#   - the password reaches helm on stdin (--password-stdin), never in its
#     arguments, and is never printed
#   - xtrace that a job turns on for every step (SHELLOPTS, or set -x in
#     $BASH_ENV) is off before the credentials are read
#   - a credential variable that is unset reaches helm as an empty value, so
#     helm reports it, rather than the script stopping on set -u
#   - a password of -n reaches helm intact (echo would take it as an option)
#   - without plain_http, helm gets no extra login flags, even on bash < 4.4
#
# The circleci CLI is stubbed when it isn't on the PATH.
#
# Run from a checkout:
#   bash <this file>

set -uo pipefail

# Find the repository root, the directory that holds src/@orb.yml.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
until [[ -f "${ROOT}/src/@orb.yml" ]]; do
    if [[ "${ROOT}" == "/" ]]; then
        echo "FAIL: no src/@orb.yml above ${BASH_SOURCE[0]}"
        exit 1
    fi
    ROOT=$(dirname "${ROOT}")
done
SCRIPT="${ROOT}/src/scripts/registry_login.sh"

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin"

# A stand-in for the circleci CLI, which only has to substitute nothing.
if ! command -v circleci > /dev/null 2>&1; then
    printf '#!/bin/sh\ncat\n' > "${WORK}/bin/circleci"
    chmod +x "${WORK}/bin/circleci"
fi

# Records helm's arguments, one per line, and its stdin.
cat > "${WORK}/bin/helm" << EOF
#!/bin/bash
printf '%s\n' "\$@" > "${WORK}/helm-args"
cat > "${WORK}/helm-stdin"
exit "\${HELM_EXIT:-0}"
EOF
chmod +x "${WORK}/bin/helm"

TEST_USERNAME="ci-user"
# shellcheck disable=SC2016 # the $ is part of the password, not an expansion
TEST_PASSWORD='s3cret "quoted" $HOME value'

FAILURES=0
RC=0
OUTPUT=""

# run_login [VAR=value ...]: runs registry_login.sh with default parameters,
# overridden by the given assignments, and sets RC and OUTPUT. (Bash 4.0
# takes an empty "$@" for an unbound variable, so the assignments are copied
# only when there are some.)
run_login() {
    local -a vars=()
    if [[ $# -gt 0 ]]; then
        vars=("$@")
    fi
    rm -f "${WORK}/helm-args" "${WORK}/helm-stdin"
    OUTPUT=$(env -u BASH_ENV \
        PATH="${WORK}/bin:${PATH}" \
        REGISTRY_USERNAME="${TEST_USERNAME}" \
        REGISTRY_PASSWORD="${TEST_PASSWORD}" \
        PARAM_USERNAME="REGISTRY_USERNAME" \
        PARAM_PASSWORD="REGISTRY_PASSWORD" \
        PARAM_REGISTRY="registry.example:5000" \
        PARAM_PLAIN_HTTP="false" \
        ${vars[@]+"${vars[@]}"} \
        bash "${SCRIPT}" 2>&1)
    RC=$?
}

# check DESCRIPTION COMMAND...: records a failure, with the output, unless
# COMMAND succeeds.
check() {
    local description=$1
    shift
    if "$@"; then
        printf 'ok: %s\n' "${description}"
    else
        printf 'FAIL: %s\n' "${description}"
        printf '    | %s\n' "${OUTPUT}"
        FAILURES=$((FAILURES + 1))
    fi
}
rc_is_zero() { [[ "${RC}" -eq 0 ]]; }
rc_is_nonzero() { [[ "${RC}" -ne 0 ]]; }
output_lacks() { ! grep -qF -- "$1" <<< "${OUTPUT}"; }
args_have() { grep -qxF -- "$1" "${WORK}/helm-args"; }
args_lack() { ! grep -qF -- "$1" "${WORK}/helm-args"; }
stdin_is() { [[ -f "${WORK}/helm-stdin" && "$(cat "${WORK}/helm-stdin")" == "$1" ]]; }
args_are() { [[ -f "${WORK}/helm-args" && "$(cat "${WORK}/helm-args")" == "$(printf '%s\n' "$@")" ]]; }

run_login
check "logs in" rc_is_zero
check "runs helm registry login" args_have "login"
check "passes the registry" args_have "registry.example:5000"
check "passes the username" args_have "${TEST_USERNAME}"
check "reads the password from stdin" args_have "--password-stdin"
check "sends the password on stdin" stdin_is "${TEST_PASSWORD}"
check "keeps the password off helm's command line" args_lack "s3cret"
check "never prints the password" output_lacks "s3cret"
check "does not pass --plain-http by default" args_lack "--plain-http"

run_login PARAM_PLAIN_HTTP="true"
check "passes --plain-http when asked" args_have "--plain-http"

# Without plain_http, LOGIN_FLAGS is empty. Bash before 4.4 treats an empty
# array as unset under set -u, so an unguarded "${LOGIN_FLAGS[@]}" stops the
# script before helm runs. The exact arguments also rule out an empty one.
run_login PARAM_PLAIN_HTTP="false"
check "logs in without extra login flags" rc_is_zero
check "runs helm with no extra login flags" \
    args_are registry login --debug "registry.example:5000" -u "${TEST_USERNAME}" --password-stdin

# echo would take a password of -n as its own option and send nothing.
run_login REGISTRY_PASSWORD="-n"
check "logs in with a password of -n" rc_is_zero
check "sends a password of -n on stdin" stdin_is "-n"

run_login SHELLOPTS=xtrace
check "logs in with xtrace turned on for the job" rc_is_zero
check "turns xtrace off before reading the credentials" output_lacks "s3cret"

run_login PARAM_PASSWORD="UNSET_TEST_PASSWORD"
check "leaves an unset password variable for helm to report" rc_is_zero
check "sends an empty password for an unset variable" stdin_is ""
check "does not stop on the unset variable" output_lacks "unbound variable"

run_login HELM_EXIT=1
check "fails when helm registry login fails" rc_is_nonzero

if [[ "${FAILURES}" -gt 0 ]]; then
    echo "${FAILURES} failure(s)"
    exit 1
fi
echo "All registry login tests passed."
