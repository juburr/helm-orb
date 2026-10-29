#!/usr/bin/env bash
#
# Tests src/scripts/upload.sh against a local HTTPS server that uses a
# self-signed certificate, which curl trusts through CURL_CA_BUNDLE:
#
#   - only https:// URLs are accepted, and others are refused before any request
#   - a directory URL gets the chart's file name appended; a file URL is used as is
#   - the credentials come from the named variables and never appear in
#     curl's arguments
#   - HTTP error responses, redirects and connection failures fail the step,
#     and print the response code and body
#   - unset credentials and invalid variable names are refused
#   - errors go to stderr and start with ERROR:, and curl only speaks https
#
# Needs python3, openssl and curl. The circleci CLI is stubbed when it isn't on
# the PATH.
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
SCRIPT="${ROOT}/src/scripts/upload.sh"

for tool in python3 openssl curl; do
    if ! command -v "${tool}" > /dev/null 2>&1; then
        echo "FAIL: ${tool} is required to run these tests"
        exit 1
    fi
done

WORK=$(mktemp -d)
SERVER_PID=""
cleanup() {
    if [[ -n "${SERVER_PID}" ]]; then
        kill "${SERVER_PID}" 2> /dev/null
    fi
    rm -rf "${WORK}"
}
trap cleanup EXIT
mkdir -p "${WORK}/bin" "${WORK}/tmp"

# A stand-in for the circleci CLI, which only has to substitute nothing.
if ! command -v circleci > /dev/null 2>&1; then
    printf '#!/bin/sh\ncat\n' > "${WORK}/bin/circleci"
    chmod +x "${WORK}/bin/circleci"
fi

# Records curl's arguments, then runs the real curl with the same stdin.
cat > "${WORK}/bin/curl" << EOF
#!/bin/bash
printf '%s\n' "\$@" >> "${WORK}/curl-args"
exec "$(command -v curl)" "\$@"
EOF
chmod +x "${WORK}/bin/curl"

openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=127.0.0.1" \
    -addext "subjectAltName=IP:127.0.0.1" \
    -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" > /dev/null 2>&1

# Logs each PUT's path and Authorization header, saves its body, and responds
# by path: /denied/ with 401, /broken/ with 500, /moved/ with 302, else 201.
cat > "${WORK}/server.py" << 'EOF'
import http.server, ssl, sys

work = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_PUT(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        with open(f"{work}/requests", "a") as log:
            log.write(f"PUT {self.path} {self.headers.get('Authorization', '-')}\n")
        with open(f"{work}/received", "wb") as received:
            received.write(body)
        status, reply = 201, b""
        if self.path.startswith("/denied/"):
            status, reply = 401, b"Invalid credentials for this repository"
        elif self.path.startswith("/broken/"):
            status, reply = 500, b"Repository storage is unavailable"
        elif self.path.startswith("/moved/"):
            status = 302
        self.send_response(status)
        if status == 302:
            self.send_header("Location", "/elsewhere/")
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    def log_message(self, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(f"{work}/cert.pem", f"{work}/key.pem")
server.socket = context.wrap_socket(server.socket, server_side=True)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
python3 "${WORK}/server.py" "${WORK}" > "${WORK}/port" 2> "${WORK}/server.log" &
SERVER_PID=$!
for _ in $(seq 1 100); do
    [[ -s "${WORK}/port" ]] && break
    sleep 0.1
done
if [[ ! -s "${WORK}/port" ]]; then
    echo "FAIL: the test HTTPS server did not start"
    cat "${WORK}/server.log"
    exit 1
fi
SERVER="https://127.0.0.1:$(cat "${WORK}/port")"

CHART_DIR="${WORK}/dist"
mkdir -p "${CHART_DIR}"
CHART="${CHART_DIR}/mychart-1.0.0.tgz"
echo "not really a chart" > "${CHART}"

TEST_USERNAME="ci-user"
# Characters that curl's config syntax needs escaped, and a colon.
TEST_PASSWORD=$'p@ss "quoted" back\\slash\ttab $HOME:colon'
expected_auth() {
    printf 'Basic %s' "$(printf '%s:%s' "$1" "$2" | base64 | tr -d '\n')"
}

FAILURES=0
RC=0
OUTPUT=""
STDOUT=""
STDERR=""

# run_upload [VAR=value ...]: runs upload.sh with default parameters,
# overridden by the given assignments, and sets RC, STDOUT, STDERR, and
# OUTPUT (stdout followed by stderr). (Bash 4.0 takes an empty "$@" for an
# unbound variable, so the assignments are copied only when there are some.)
run_upload() {
    local -a vars=()
    if [[ $# -gt 0 ]]; then
        vars=("$@")
    fi
    rm -f "${WORK}/requests" "${WORK}/received" "${WORK}/curl-args"
    env -u BASH_ENV -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy -u ALL_PROXY -u all_proxy \
        PATH="${WORK}/bin:${PATH}" \
        TMPDIR="${WORK}/tmp" \
        CURL_HOME="${WORK}" \
        CURL_CA_BUNDLE="${WORK}/cert.pem" \
        HELM_REPO_USERNAME="${TEST_USERNAME}" \
        HELM_REPO_PASSWORD="${TEST_PASSWORD}" \
        PARAM_CHART="${CHART}" \
        PARAM_URL="${SERVER}/charts/" \
        PARAM_USERNAME="HELM_REPO_USERNAME" \
        PARAM_PASSWORD="HELM_REPO_PASSWORD" \
        ${vars[@]+"${vars[@]}"} \
        bash "${SCRIPT}" > "${WORK}/stdout" 2> "${WORK}/stderr"
    RC=$?
    STDOUT=$(cat "${WORK}/stdout")
    STDERR=$(cat "${WORK}/stderr")
    OUTPUT="${STDOUT}"$'\n'"${STDERR}"
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
# stderr_has LINE: LINE is a whole line of stderr, and not on stdout.
stderr_has() { grep -qxF -- "$1" <<< "${STDERR}" && ! grep -qF -- "$1" <<< "${STDOUT}"; }
stdout_has() { grep -qF -- "$1" <<< "${STDOUT}"; }
no_error_on_stdout() { ! grep -qF -- "ERROR:" <<< "${STDOUT}"; }
request_was() { [[ "$(cat "${WORK}/requests" 2> /dev/null)" == "PUT $1 $2" ]]; }
no_request() { [[ ! -e "${WORK}/requests" ]]; }
curl_not_run() { [[ ! -e "${WORK}/curl-args" ]]; }
args_lack() { ! grep -qF -- "$1" "${WORK}/curl-args"; }
first_arg_is() { [[ "$(head -n 1 "${WORK}/curl-args")" == "$1" ]]; }
# args_start_with ARG...: curl's first arguments are exactly ARG...
args_start_with() { [[ "$(head -n "$#" "${WORK}/curl-args")" == "$(printf '%s\n' "$@")" ]]; }
tmp_is_empty() { [[ -z "$(ls -A "${WORK}/tmp")" ]]; }

for url in "http://nexus.example/charts/" "https-nexus.example/charts/" "nexus.example/charts/"; do
    run_upload PARAM_URL="${url}"
    check "rejects ${url}" rc_is_nonzero
    check "explains why ${url} is rejected" output_has "requires a url starting with 'https://'"
    check "prints the ${url} error on stderr" stderr_has "ERROR: The upload command requires a url starting with 'https://'."
    check "prints the ${url} error's second line on stderr" stderr_has "Credentials are included within request headers."
    check "prints no error on stdout for ${url}" no_error_on_stdout
    check "does not contact ${url}" curl_not_run
    check "prints no response code for ${url}" output_lacks "Response code"
done

run_upload
check "uploads to a directory URL" rc_is_zero
check "appends the chart's file name to a directory URL" \
    request_was "/charts/mychart-1.0.0.tgz" "$(expected_auth "${TEST_USERNAME}" "${TEST_PASSWORD}")"
check "uploads the chart's contents" cmp -s "${CHART}" "${WORK}/received"
check "prints the response code" output_has "Response code: 201"
check "prints where the chart was uploaded" output_has "Uploaded ${CHART} to ${SERVER}/charts/mychart-1.0.0.tgz."
check "keeps the password off curl's command line" args_lack "${TEST_PASSWORD}"
check "keeps the username off curl's command line" args_lack "${TEST_USERNAME}"
check "keeps the encoded credentials off curl's command line" \
    args_lack "$(expected_auth "${TEST_USERNAME}" "${TEST_PASSWORD}" | cut -d' ' -f2)"
check "never prints the password" output_lacks "${TEST_PASSWORD}"
check "removes its temporary files" tmp_is_empty
check "passes --disable first, then --proto =https" args_start_with "--disable" "--proto" "=https"
check "prints nothing on stderr after a successful upload" [ -z "${STDERR}" ]
check "prints the response code on stdout" stdout_has "Response code: 201"

# A job can turn xtrace on for every step through SHELLOPTS or a set -x in
# BASH_ENV. upload turns it off before it reads the credentials.
run_upload SHELLOPTS=xtrace
check "uploads with xtrace turned on for the job" rc_is_zero
# xtrace quotes the tab as $'...\t...', so look for a part it prints as is.
check "turns xtrace off before reading the credentials" output_lacks 'p@ss "quoted"'
check "does not trace the encoded credentials" \
    output_lacks "$(expected_auth "${TEST_USERNAME}" "${TEST_PASSWORD}" | cut -d' ' -f2)"

run_upload PARAM_URL="${SERVER}/charts/renamed-1.0.0.tgz"
check "uploads to a file URL" rc_is_zero
check "uses a file URL as is" \
    request_was "/charts/renamed-1.0.0.tgz" "$(expected_auth "${TEST_USERNAME}" "${TEST_PASSWORD}")"

run_upload PARAM_USERNAME="NEXUS_USER" PARAM_PASSWORD="NEXUS_PASSWORD" NEXUS_USER="nexus-user" NEXUS_PASSWORD="nexus-password"
check "reads credentials from the named variables" rc_is_zero
check "sends the named variables' credentials" \
    request_was "/charts/mychart-1.0.0.tgz" "$(expected_auth "nexus-user" "nexus-password")"

run_upload PARAM_URL="${SERVER}/denied/"
check "fails on HTTP 401" rc_is_nonzero
check "prints the 401 response code" output_has "Response code: 401"
check "explains the 401 failure" output_has "the server responded with HTTP 401"
check "prints the 401 response body" output_has "Invalid credentials for this repository"
check "prints the 401 failure on stderr" stderr_has "ERROR: The upload failed: the server responded with HTTP 401."
check "prints the 401 response body on stderr" stderr_has "Invalid credentials for this repository"
check "prints no error on stdout for the 401" no_error_on_stdout
check "removes its temporary files after a failure" tmp_is_empty

run_upload PARAM_URL="${SERVER}/broken/"
check "fails on HTTP 500" rc_is_nonzero
check "prints the 500 response code" output_has "Response code: 500"
check "prints the 500 response body" output_has "Repository storage is unavailable"

run_upload PARAM_URL="${SERVER}/moved/"
check "fails on a redirect, which is not followed" rc_is_nonzero
check "prints the redirect's response code" output_has "Response code: 302"

# A runner's .curlrc must not change what upload does: with location there,
# curl would follow the redirect to a 201 and report success.
printf 'location\n' > "${WORK}/.curlrc"
run_upload PARAM_URL="${SERVER}/moved/"
rm -f "${WORK}/.curlrc"
check "passes --disable as curl's first argument" first_arg_is "--disable"
check "ignores a .curlrc that follows redirects" rc_is_nonzero
check "stops at the redirect despite the .curlrc" output_has "Response code: 302"

run_upload PARAM_URL="https://127.0.0.1:9/charts/"
check "fails when the server is unreachable" rc_is_nonzero
check "explains the connection failure" output_has "curl exited with code 7"
check "prints the connection failure on stderr" stderr_has "ERROR: The upload failed: curl exited with code 7."

run_upload HELM_REPO_PASSWORD=""
check "refuses an empty password variable" rc_is_nonzero
check "names the empty password variable" output_has "\$HELM_REPO_PASSWORD, named by the password parameter, is unset or empty."
check "names the empty password variable on stderr" stderr_has "ERROR: \$HELM_REPO_PASSWORD, named by the password parameter, is unset or empty."
check "does not upload without a password" curl_not_run

run_upload PARAM_USERNAME="UNSET_TEST_USERNAME"
check "refuses an unset username variable" rc_is_nonzero
check "names the unset username variable" output_has "\$UNSET_TEST_USERNAME, named by the username parameter, is unset or empty."
check "names the unset username variable on stderr" stderr_has "ERROR: \$UNSET_TEST_USERNAME, named by the username parameter, is unset or empty."

run_upload PARAM_PASSWORD="hunter2 secret"
check "refuses a password parameter that isn't a variable name" rc_is_nonzero
check "explains the invalid password parameter" output_has "The password parameter must be the name of an environment variable."
check "explains the invalid password parameter on stderr" stderr_has "ERROR: The password parameter must be the name of an environment variable."
check "does not print the invalid password parameter" output_lacks "hunter2"

run_upload PARAM_CHART="${CHART_DIR}/missing-1.0.0.tgz"
check "refuses a missing chart" rc_is_nonzero
check "explains the missing chart" output_has "is not a file"
check "explains the missing chart on stderr" stderr_has "ERROR: The chart '${CHART_DIR}/missing-1.0.0.tgz' is not a file."
check "does not upload a missing chart" no_request

if [[ "${FAILURES}" -gt 0 ]]; then
    echo "${FAILURES} failure(s)"
    exit 1
fi
echo "All upload tests passed."
