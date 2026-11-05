# Security Policy

## Threat model

This image runs the [Pi coding agent](https://github.com/earendil-works/pi), which has
**no tool-approval gate**: model-generated `bash`, `edit` and `write` calls run immediately.
Prompt injection from repository contents, tool output or web content can steer those
calls. **The container, and whatever runs it, is the security boundary.**

This repo is responsible for:

- a minimal, digest-pinned image that runs as a non-root user (UID 1000);
- containing no credentials or configuration;
- a reproducible, attested build (SLSA provenance, SBOM, cosign signature).

You, the operator, are responsible for what you expose to the container: credentials,
mounted files, the network, and Kubernetes API access. See the hardened example in
[`examples/k8s/`](examples/k8s/).

## Supported versions

Only the latest release tag gets fixes. Base-image and Pi updates arrive through
Renovate PRs and new `v<pi-version>-<revision>` releases.

## Reporting a vulnerability

- **Issues in this image** (Dockerfile, workflows, examples): use
  [GitHub private vulnerability reporting](https://github.com/pfrybar/pi-agent/security/advisories/new).
  Please don't open a public issue.
- **Issues in Pi itself:** report them upstream to
  [earendil-works/pi](https://github.com/earendil-works/pi/security).
- **Issues in the base image** (`node:24-bookworm-slim`, Debian packages): report them
  upstream. Rebuilds pick up fixes once the digest is bumped.

Expect an acknowledgement within 7 days.

## Verifying images

```bash
IMAGE=ghcr.io/pfrybar/pi-agent:1.5.0-1

# GitHub build provenance attestation
gh attestation verify "oci://$IMAGE" --repo pfrybar/pi-agent

# cosign keyless signature (GitHub Actions OIDC identity)
cosign verify "$IMAGE" \
  --certificate-identity-regexp '^https://github.com/pfrybar/pi-agent/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
