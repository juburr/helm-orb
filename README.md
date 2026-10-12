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

## Features
### **Secure By Design**
- **Least Privilege**: Installs to a user-owned directory by default, with no `sudo` usage anywhere in this orb.
- **Integrity**: Checksum validation of all downloaded binaries using SHA-512. Helm versions without a checksum in this orb fail closed by default (`verify_checksums: strict`); set `verify_checksums: known_versions` to install them unverified with a warning.
- **Provenance**: Installs directly from Helm's [official webpage](https://helm.sh/). No third-party websites, domains, or proxies are used.
- **Confidentiality**: All secrets and environment variables are handled in accordance with CircleCI's [security recommendations](https://circleci.com/docs/security-recommendations/) and [best practices](https://circleci.com/docs/orbs-best-practices/).
- **Privacy**: No usage data of any kind is collected or shipped back to the orb developer.

Info for security teams:
- Required external access to allow, if running a locked down, self-hosted CircleCI pipeline on-prem:
  - `get.helm.sh`: For download and installation of the Helm tool.

### **Platform Support**
- Linux executors on `amd64` (`x86_64`) and `arm64` (`aarch64`), including CircleCI's Arm resource classes. The `install` command selects the matching Helm build and verifies it against a per-architecture SHA-512 checksum. Other platforms fail with an error.
