#!/usr/bin/env bash
#
# Tests the scripts of package, locate_chart, push, registry_login and
# registry_logout the way the GitHub Actions run them: with no circleci CLI on
# the PATH, against a stand-in helm that records its arguments. It checks that:
#
#   - without the CLI, values reach helm as they are: "$NAME" is not expanded,
#     and a value starting with "-" is not taken for an option
#   - plain_http takes true or false, as the actions pass it, and CircleCI's
#     1 or 0, and anything else fails before helm runs
#   - registry_login refuses a username or password that isn't a variable
#     name, without printing it
#   - package and locate_chart write the chart's absolute path to BASH_ENV
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
SCRIPTS="${ROOT}/src/scripts"

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

# The PATH the scripts run with: links to just the tools they need, and a
# stand-in helm. CircleCI's images have the circleci CLI in /bin and
# /usr/bin, so the system directories can't be on it.
TOOLS="${WORK}/tools"
mkdir -p "${TOOLS}"
for tool in bash cat dirname find head mkdir mktemp realpath rm sed tee; do
    if ! path=$(command -v "${tool}"); then
        echo "FAIL: ${tool} is required to run these tests"
        exit 1
    fi
    ln -s "${path}" "${TOOLS}/${tool}"
done

# Records helm's arguments, one per line, and its stdin. helm package writes
# an empty chart to its --destination and reports it as Helm does.
cat > "${TOOLS}/helm" << EOF
#!${TOOLS}/bash
printf '%s\n' "\$@" > "${WORK}/helm-args"
${TOOLS}/cat > "${WORK}/helm-stdin"
if [[ "\$1" == package ]]; then
    destination="" version=""
    while [[ \$# -gt 0 ]]; do
        case "\$1" in
            --destination) destination=\$2; shift ;;
            --version) version=\$2; shift ;;
        esac
        shift
    done
    : > "\${destination}/testchart-\${version}.tgz"
    echo "Successfully packaged chart and saved it to: \${destination}/testchart-\${version}.tgz"
fi
exit "\${HELM_EXIT:-0}"
EOF
chmod +x "${TOOLS}/helm"

FAILURES=0
RC=0
OUTPUT=""

# run SCRIPT [VAR=value ...]: runs a script from src/scripts with the PATH
# above, a fresh BASH_ENV, and the given parameters. Sets RC and OUTPUT.
run() {
    local script=$1
    shift
    rm -f "${WORK}/helm-args" "${WORK}/helm-stdin"
    : > "${WORK}/bash-env"
    OUTPUT=$(env -i HOME="${WORK}" PATH="${TOOLS}" BASH_ENV="${WORK}/bash-env" "$@" \
        "${TOOLS}/bash" "${SCRIPTS}/${script}.sh" < /dev/null 2>&1)
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
output_has() { grep -qF -- "$1" <<< "${OUTPUT}"; }
output_lacks() { ! grep -qF -- "$1" <<< "${OUTPUT}"; }
helm_ran() { [[ -f "${WORK}/helm-args" ]]; }
helm_did_not_run() { [[ ! -f "${WORK}/helm-args" ]]; }
args_are() { [[ -f "${WORK}/helm-args" && "$(cat "${WORK}/helm-args")" == "$(printf '%s\n' "$@")" ]]; }
bash_env_is() { [[ "$(cat "${WORK}/bash-env")" == "$1" ]]; }

check "the scripts run with no circleci CLI on the PATH" \
    bash -c "! PATH='${TOOLS}' command -v circleci"

# ------------------------------------------------------------------- push
# shellcheck disable=SC2016 # $HOME is part of the value, not an expansion
PUSH_DEFAULTS=(PARAM_CHART='$HOME/chart.tgz' PARAM_REMOTE='-oci://localhost:5000/charts' PARAM_PLAIN_HTTP=false)
run push "${PUSH_DEFAULTS[@]}"
check "push: succeeds" rc_is_zero
# shellcheck disable=SC2016 # the values are passed as they are
check "push: passes values as they are, \$NAME and leading - included" \
    args_are push --debug '$HOME/chart.tgz' '-oci://localhost:5000/charts'
for value in true 1; do
    run push "${PUSH_DEFAULTS[@]}" PARAM_PLAIN_HTTP="${value}"
    # shellcheck disable=SC2016 # the values are passed as they are
    check "push: plain_http ${value} passes --plain-http" \
        args_are push --debug --plain-http '$HOME/chart.tgz' '-oci://localhost:5000/charts'
done
run push "${PUSH_DEFAULTS[@]}" PARAM_PLAIN_HTTP=0
# shellcheck disable=SC2016 # the values are passed as they are
check "push: plain_http 0 passes no --plain-http" \
    args_are push --debug '$HOME/chart.tgz' '-oci://localhost:5000/charts'
run push "${PUSH_DEFAULTS[@]}" PARAM_PLAIN_HTTP=yes
check "push: plain_http yes fails" rc_is_nonzero
check "push: saying what plain_http takes" output_has "ERROR: plain_http must be true or false, not 'yes'."
check "push: before helm runs" helm_did_not_run
run push "${PUSH_DEFAULTS[@]}" HELM_EXIT=1
check "push: fails when helm push fails" rc_is_nonzero

# --------------------------------------------------------- registry_login
LOGIN_DEFAULTS=(REGISTRY_USERNAME=ci-user REGISTRY_PASSWORD=ci-password PARAM_USERNAME=REGISTRY_USERNAME
    PARAM_PASSWORD=REGISTRY_PASSWORD PARAM_REGISTRY='-localhost:5000' PARAM_PLAIN_HTTP=false)
run registry_login "${LOGIN_DEFAULTS[@]}"
check "registry_login: succeeds" rc_is_zero
check "registry_login: passes the registry as it is" \
    args_are registry login --debug '-localhost:5000' -u ci-user --password-stdin
run registry_login "${LOGIN_DEFAULTS[@]}" PARAM_PLAIN_HTTP=true
check "registry_login: plain_http true passes --plain-http" \
    args_are registry login --debug --plain-http '-localhost:5000' -u ci-user --password-stdin
run registry_login "${LOGIN_DEFAULTS[@]}" PARAM_PLAIN_HTTP=on
check "registry_login: plain_http on fails" rc_is_nonzero
check "registry_login: saying what plain_http takes" output_has "ERROR: plain_http must be true or false, not 'on'."
check "registry_login: before helm runs" helm_did_not_run
run registry_login "${LOGIN_DEFAULTS[@]}" PARAM_PASSWORD='not-a-name s3cret'
check "registry_login: a password that isn't a variable name fails" rc_is_nonzero
check "registry_login: saying it must be a name" \
    output_has "ERROR: The password parameter must be the name of an environment variable."
check "registry_login: without printing it" output_lacks "s3cret"
check "registry_login: before helm runs" helm_did_not_run
run registry_login "${LOGIN_DEFAULTS[@]}" PARAM_USERNAME='ci user'
check "registry_login: a username that isn't a variable name fails" rc_is_nonzero
check "registry_login: and says so" \
    output_has "ERROR: The username parameter must be the name of an environment variable."

# -------------------------------------------------------- registry_logout
run registry_logout PARAM_REGISTRY='-localhost:5000'
check "registry_logout: succeeds" rc_is_zero
check "registry_logout: passes the registry as it is" args_are registry logout --debug '-localhost:5000'

# ---------------------------------------------------------------- package
mkdir -p "${WORK}/chart" "${WORK}/chart packages"
# shellcheck disable=SC2016 # $APP_VERSION is part of the value, not an expansion
run package PARAM_APP_VERSION='$APP_VERSION' PARAM_CHART_DIR="${WORK}/chart" PARAM_CHART_VERSION=0.1.0 \
    PARAM_OUTPUT_DIR="${WORK}/chart packages/" PARAM_PACKAGE_ENV_VAR=HELM_PACKAGE
check "package: succeeds" rc_is_zero
# shellcheck disable=SC2016 # the value is passed as it is
check "package: passes values as they are" \
    args_are package --app-version '$APP_VERSION' --destination "${WORK}/chart packages" --debug --version 0.1.0 "${WORK}/chart"
check "package: writes the chart's absolute path to BASH_ENV" \
    bash_env_is "$(printf 'export %s=%q' HELM_PACKAGE "${WORK}/chart packages/testchart-0.1.0.tgz")"

# ----------------------------------------------------------- locate_chart
run locate_chart PARAM_CHART_NAME=testchart PARAM_CHART_VERSION=0.1.0 PARAM_PACKAGE_ENV_VAR=LOCATED_CHART \
    PARAM_SEARCH_DIR="${WORK}/chart packages"
check "locate_chart: succeeds" rc_is_zero
check "locate_chart: writes the chart's absolute path to BASH_ENV" \
    bash_env_is "$(printf 'export %s=%q' LOCATED_CHART "${WORK}/chart packages/testchart-0.1.0.tgz")"
run locate_chart PARAM_CHART_NAME=otherchart PARAM_CHART_VERSION="" PARAM_PACKAGE_ENV_VAR=LOCATED_CHART \
    PARAM_SEARCH_DIR="${WORK}/chart packages"
check "locate_chart: fails when no chart matches" rc_is_nonzero
check "locate_chart: and says so" output_has "ERROR: Unable to locate a Helm chart with the supplied parameters."

if [[ "${FAILURES}" -gt 0 ]]; then
    echo "${FAILURES} failure(s)"
    exit 1
fi
echo "All command script tests passed."
