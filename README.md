<div align="center">
  <img align="center" width="320" src="assets/logos/helm-orb-logo.png" alt="Helm Orb">
  <h1>CircleCI Helm Orb</h1>
  <i>An orb for simplifying Helm installation and use within CircleCI.</i><br /><br />
</div>

[![CircleCI Build Status](https://circleci.com/gh/juburr/helm-orb.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/juburr/helm-orb) [![CircleCI Orb Version](https://badges.circleci.com/orbs/juburr/helm-orb.svg)](https://circleci.com/developer/orbs/orb/juburr/helm-orb) [![GitHub License](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/juburr/helm-orb/master/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)

This is an unofficial Helm orb used for installing Helm in your CircleCI pipeline and publishing Helm charts for use in Kubernetes deployments. Contributions are welcome!

> [!IMPORTANT]
> **Version 0.7.0 changed the default Helm version from 3.18.6 to 4.3.0 (Helm 4).** If you upgraded the orb without setting `version` on `install`, your pipeline now runs Helm 4. Pin the Helm version you need, and pin the orb to an exact release so that future default changes only reach you when you choose to upgrade:
>
> ```yaml
> orbs:
>   helm: juburr/helm-orb@0.8.0
> jobs:
>   publish-chart:
>     docker:
>       - image: cimg/base:current-22.04
>     steps:
>       - helm/install:
>           version: "3.22.0" # or "4.3.0"
> ```
>
> Behavior differences between Helm 3 and Helm 4 that affect this orb:
> - `registry_login`: Helm 4 accepts a hostname only (for example `ghcr.io`, not `https://ghcr.io`), and it no longer falls back to plain HTTP. Set `plain_http: true` for registries without TLS (available from orb 0.8.0).
> - Both major versions are tested in this orb's CI: `install`, `package`, `locate_chart`, `registry_login`, `push`, and `registry_logout` run against Helm 3.22.0 and the default Helm 4 release.
>
> Helm 3 stopped receiving bug fixes on September 9, 2026 and receives security fixes until February 10, 2027 ([announcement](https://helm.sh/blog/helm-v3-end-of-life)).

## Upgrading

The next release renames a command and several parameters, to use Helm's own terms and the names the other juburr orbs use. Update your config as follows:

| Old | New |
| --- | --- |
| `push_raw` command | `upload` command |
| `push_raw.upload_path` | `upload.url` |
| `push_raw.username_env` (default `NEXUS_USER`) | `upload.username` (default `HELM_REPO_USERNAME`) |
| `push_raw.password_env` (default `NEXUS_PASSWORD`) | `upload.password` (default `HELM_REPO_PASSWORD`) |
| `package.chart_directory` | `package.chart_dir` |
| `package.output_directory` | `package.output_dir` |
| `package.env_output_package` | `package.package_env_var` |
| `locate_chart.env_output_package` | `locate_chart.package_env_var` |
| `locate_chart.search_directory` | `locate_chart.search_dir` |
| `push.registry` | `push.remote` |
| `registry_login.username_env` (default `GITHUB_USER`) | `registry_login.username` (default `REGISTRY_USERNAME`) |
| `registry_login.password_env` (default `GITHUB_TOKEN`) | `registry_login.password` (default `REGISTRY_PASSWORD`) |

If you relied on the old default credential variables, either rename those variables in your contexts or project settings, or pass their old names, for example `username: NEXUS_USER`.

Behavior changes:
- `upload` fails the step when the server responds with anything other than a 2xx status, and prints the response code and body. `push_raw` reported success on HTTP errors such as 401 or 500. The credentials now reach curl on stdin instead of its command line, and `upload` fails if either credential variable is unset or empty.
- `package` and `locate_chart` shell-quote the path they export through `BASH_ENV`, so paths containing spaces or other special characters reach later steps intact.

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
  - `registry_login` and `push`: the registry you pass (`registry_login`'s `registry`, or the host in `push`'s `remote`), plus any other host that registry directs Helm to, such as a token service it delegates authentication to (for example, Docker Hub uses `auth.docker.io`) or a separate upload endpoint named in its responses.
  - `upload`: the `url` you pass.
- `package`, `locate_chart`, and `registry_logout` make no network requests.
- With `caching` enabled (the default), `install` also uses CircleCI's cache storage through the built-in `restore_cache` and `save_cache` steps. On CircleCI cloud with self-hosted runners, that requires outbound HTTPS to `circleci-tasks-prod.s3.us-east-1.amazonaws.com` (see the [runner FAQ](https://circleci.com/docs/guides/execution-runner/runner-faqs/#what-connectivity-is-required)). Set `caching: false` to avoid it.

### **Platform Support**
- Linux executors on `amd64` (`x86_64`) and `arm64` (`aarch64`), including CircleCI's Arm resource classes. The `install` command selects the matching Helm build and verifies it against a per-architecture SHA-512 checksum. Other platforms fail with an error.
