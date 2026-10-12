<div align="center">
  <img align="center" width="320" src="assets/logos/helm-orb-logo.png" alt="Helm Orb">
  <h1>CircleCI Helm Orb</h1>
  <i>An orb for simplifying Helm installation and use within CircleCI.</i><br /><br />
</div>

[![CircleCI Build Status](https://circleci.com/gh/juburr/helm-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/juburr/helm-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/juburr/helm-orb.svg)](https://circleci.com/developer/orbs/orb/juburr/helm-orb) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/juburr/helm-orb/master/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

This is an unofficial Helm orb used for installing Helm in your CircleCI pipeline and publishing Helm charts for use in Kubernetes deployments. Contributions are welcome!

## Features
### **Secure By Design**
- **Least Privilege**: Installs to a user-owned directory by default, with no `sudo` usage anywhere in this orb.
- **Integrity**: Checksum validation of all downloaded binaries using SHA-512. Helm versions without a checksum in this orb fail closed by default (`verify_checksums: strict`); set `verify_checksums: known_versions` to install them unverified with a warning.
- **Provenance**: Installs directly from Helm's [official webpage](https://helm.sh/). No third-party websites, domains, or proxies are used.
- **Confidentiality**: All secrets and environment variables are handled in accordance with CircleCI's [security recommendations](https://circleci.com/docs/security-recommendations/) and [best practices](https://circleci.com/docs/orbs-best-practices/).
- **Privacy**: No usage data of any kind is collected or shipped back to the orb developer.

Info for security teams:
- Required external access to allow, if running a locked down, self-hosted CircleCI pipeline on-prem:
  - `get.helm.sh`: For download and installation of the Helm tool. This is the only host the orb's scripts contact on their own. Downloads are served directly from it, with no redirects to other hosts.
- Hosts you configure, contacted only by the commands that take them:
  - `registry_login` and `push`: the registry you pass, plus any other host that registry directs Helm to, such as a token service it delegates authentication to (for example, Docker Hub uses `auth.docker.io`) or a separate upload endpoint named in its responses.
  - `push_raw`: the `upload_path` you pass.
- `package`, `locate_chart`, and `registry_logout` make no network requests.
- With `caching` enabled (the default), `install` also uses CircleCI's cache storage through the built-in `restore_cache` and `save_cache` steps. On CircleCI cloud with self-hosted runners, that requires outbound HTTPS to `circleci-tasks-prod.s3.us-east-1.amazonaws.com` (see the [runner FAQ](https://circleci.com/docs/guides/execution-runner/runner-faqs/#what-connectivity-is-required)). Set `caching: false` to avoid it.
