# pi-agent

[![build](https://github.com/pfrybar/pi-agent/actions/workflows/build.yml/badge.svg)](https://github.com/pfrybar/pi-agent/actions/workflows/build.yml)

A container image for the [Pi coding agent](https://github.com/earendil-works/pi)
(npm: [`@earendil-works/pi-coding-agent`](https://www.npmjs.com/package/@earendil-works/pi-coding-agent)),
published to `ghcr.io/pfrybar/pi-agent` for `linux/amd64` and `linux/arm64`.

It is built for **headless one-shot runs**, especially as Kubernetes Jobs:

```bash
pi -p --no-session --mode json "<prompt>"
```

Pi has no official image. This one follows the "Plain Docker" pattern from Pi's
[containerization docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/containerization.md),
plus a non-root user, a digest-pinned base, and a signed, attested release pipeline.

> [!WARNING]
> **Pi has no tool-approval gate.** Model-generated `bash`, `edit` and `write` calls run
> immediately, and prompt injection from repository contents or tool output can steer
> them. **The container is the sandbox.** Give it only the files, credentials and
> network access the task needs. Use short-lived, narrowly scoped keys; don't mount
> your host `~/.pi/agent`, Docker socket or kubeconfig; and restrict egress (see
> [`examples/k8s/networkpolicy.yaml`](examples/k8s/networkpolicy.yaml)).

## What's in the image

| | |
|---|---|
| Base | `node:24-bookworm-slim`, pinned by digest |
| Pi | `@earendil-works/pi-coding-agent@${PI_VERSION}`, installed with `--ignore-scripts` |
| Tools | `bash`, `git`, `ripgrep` (`rg`), `fd-find` (as `fd`), `ca-certificates` |
| User | `node`, UID/GID `1000:1000` (non-root) |
| Workdir | `/workspace`, owned by `node` |
| Entrypoint | `pi` (no default arguments) |
| Env | `PI_CODING_AGENT_DIR=/home/node/.pi/agent` (writable, override to a mounted path), `PI_SKIP_VERSION_CHECK=1`, `PI_TELEMETRY=0` |

No credentials or Pi configuration are baked in. Pass a provider key such as
`ANTHROPIC_API_KEY` at runtime, and settings via a mounted or copied `settings.json`.

## Usage

```bash
docker pull ghcr.io/pfrybar/pi-agent:1.5.0-1

# Version check
docker run --rm ghcr.io/pfrybar/pi-agent:1.5.0-1 --version

# One-shot run against the current directory. Pi can modify these files!
docker run --rm \
  -e ANTHROPIC_API_KEY \
  -v "$PWD:/workspace" \
  ghcr.io/pfrybar/pi-agent:1.5.0-1 \
  -p --no-session --no-approve "Summarize this repository"

# Locked-down variant: read-only rootfs, no capabilities, JSONL event output
docker run --rm --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp --tmpfs /home/node:uid=1000,gid=1000 \
  -e ANTHROPIC_API_KEY \
  -v "$PWD:/workspace" \
  ghcr.io/pfrybar/pi-agent:1.5.0-1 \
  -p --no-session --mode json --no-approve "List the failing tests" > events.jsonl

# Interactive TUI
docker run --rm -it -e ANTHROPIC_API_KEY -v "$PWD:/workspace" ghcr.io/pfrybar/pi-agent:1.5.0-1
```

Useful flags for unattended runs:

- `--no-approve` ignores trust-gated project files (`.pi/settings.json`, `.pi/extensions`,
  ...) in the workspace. Use it whenever the workspace is untrusted. Context files such as
  `AGENTS.md` and `CLAUDE.md` still load; add `--no-context-files` to skip them.
- `--tools read,grep,find,ls` restricts Pi to read-only tools for review-style tasks.
- `--offline` disables automatic network activity such as model catalog refreshes.

**Exit codes:** in `-p` (print) mode, Pi exits nonzero when the model call fails. In
`--mode json`, a failed or aborted response (for example a 401 from a bad key) appears in
the event stream as `agent_end` with `stopReason: "error"`, but **Pi still exits 0**. If
you use JSON mode in automation, check the final events to decide whether the run
succeeded.

## Tags

Releases are tagged `v<pi-version>-<revision>`, e.g. `v1.5.0-1`. Each release publishes:

| Tag | Example | Meaning |
|---|---|---|
| `<pi-version>-<revision>` | `1.5.0-1` | Immutable build. **Pin this** (or the digest). |
| `<pi-version>` | `1.5.0` | Latest image revision for this Pi version. |
| `latest` | `latest` | Most recent release. |

The revision increments when the image changes but Pi doesn't (base-image digest bump,
Dockerfile change). It resets to `1` for each new Pi version.

Every release also has:

- **SLSA build provenance** (`actions/attest-build-provenance`, pushed to GHCR);
- BuildKit **provenance** (`mode=max`) and an **SPDX SBOM** attached to the image index;
- a **cosign keyless signature** from the release workflow's GitHub OIDC identity;
- an `org.opencontainers.image.source` label linking the package to this repo.

Verify them with:

```bash
gh attestation verify oci://ghcr.io/pfrybar/pi-agent:1.5.0-1 --repo pfrybar/pi-agent

cosign verify ghcr.io/pfrybar/pi-agent:1.5.0-1 \
  --certificate-identity-regexp '^https://github.com/pfrybar/pi-agent/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

docker buildx imagetools inspect ghcr.io/pfrybar/pi-agent:1.5.0-1 --format '{{ json .SBOM }}'
```

## Kubernetes Job

[`examples/k8s/job.yaml`](examples/k8s/job.yaml) runs one prompt against a freshly cloned
repository and exits.

```bash
kubectl create secret generic pi-agent-api-keys --from-literal=ANTHROPIC_API_KEY="sk-ant-..."
kubectl apply -f examples/k8s/networkpolicy.yaml   # optional but recommended
kubectl apply -f examples/k8s/job.yaml
kubectl logs -f job/pi-agent-run -c pi              # JSONL events
```

How it fits together:

1. **`clone` initContainer**: runs `git clone --depth=1` of `$GIT_REPO`@`$GIT_REF` into
   an `emptyDir` mounted at `/workspace`. It reuses the pi-agent image, which ships git.
   For private repos, add a token from a Secret here, in the init container only, so the
   agent container never sees it.
2. **`config` initContainer**: copies `settings.json` from the `pi-agent-config`
   ConfigMap (read-only) into a writable `emptyDir` at `/pi-agent`. Pi writes to its agent
   dir at runtime (`auth.json`, `models-store.json`), so it can't use the ConfigMap mount
   directly. The example settings pick `anthropic` / `claude-sonnet-5-5` and set
   `defaultProjectTrust: "never"`.
3. **`pi` container**: runs `pi -p --no-session --mode json --no-approve "$(PI_PROMPT)"`
   with `PI_CODING_AGENT_DIR=/pi-agent`. The prompt comes from the `PI_PROMPT` env var,
   which Kubernetes expands into the args. `ANTHROPIC_API_KEY` comes from the
   `pi-agent-api-keys` Secret.

Hardening in the example:

| Setting | Why |
|---|---|
| `restartPolicy: Never`, `backoffLimit: 1` | Agent runs aren't idempotent; retry at most once. |
| `activeDeadlineSeconds: 1800` | Hard wall-clock cap for runaway loops. |
| `ttlSecondsAfterFinished: 3600` | Clean up finished Jobs and pods. |
| `automountServiceAccountToken: false` | No Kubernetes API credentials inside the pod. |
| `enableServiceLinks: false` | No env vars describing other cluster Services. |
| `runAsNonRoot`, `runAsUser: 1000` | Matches the image's `node` user. |
| `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]` | No setuid escalation or capabilities. |
| `readOnlyRootFilesystem: true` | Writes go only to the `emptyDir`s (`/workspace`, `/pi-agent`, `/home/node`, `/tmp`). |
| `seccompProfile: RuntimeDefault` | Default syscall filter. |
| `sizeLimit`s and resource limits | Bound disk, memory and CPU. |

Because of the JSON-mode exit-code behavior described above, the Job reports
`Complete` even when the model call fails. Read the logs (or drop `--mode json`) to
detect failures.

[`examples/k8s/networkpolicy.yaml`](examples/k8s/networkpolicy.yaml) denies all ingress
and egress for pods labeled `app.kubernetes.io/name: pi-agent`, then allows DNS to
kube-dns plus HTTPS to Anthropic's published API ranges and GitHub's `git` ranges. Core
NetworkPolicy only matches IP blocks, not hostnames, and those ranges drift. For FQDN
allowlists such as `api.anthropic.com` and `github.com`, use Cilium (`toFQDNs`), Calico's
DNS policy, or an egress proxy. Your CNI must enforce NetworkPolicy at all.

## Releasing

1. Bump `ARG PI_VERSION=` in the [`Dockerfile`](Dockerfile). Renovate opens this PR
   automatically when Pi publishes a new version. That ARG is the single source of truth.
2. Merge the PR once the `build` workflow is green on amd64 and arm64.
3. Tag `main` and push:

   ```bash
   git checkout main && git pull
   git tag v1.5.0-1        # v<PI_VERSION>-<revision>
   git push origin v1.5.0-1
   ```

The `release` workflow fails if the tag's Pi version doesn't match `PI_VERSION` in the
Dockerfile. Otherwise it builds both architectures, pushes the three tags, attaches the
SBOM, provenance and signature, then pulls the image back and checks `pi --version` and
the source label.

For an image-only change (such as a base digest bump), merge it and tag the next
revision, e.g. `v1.5.0-2`.

## Dependency updates

[Renovate](https://docs.renovatebot.com/) ([`renovate.json`](renovate.json); install the
[Renovate GitHub App](https://github.com/apps/renovate) on the repo) bumps:

- the `node:24-bookworm-slim` **digest**. Major Node upgrades are disabled; do those by hand.
- **GitHub Actions** commit SHAs, grouped into one PR.
- **`PI_VERSION`**, through a regex custom manager on the
  `# renovate: datasource=npm depName=@earendil-works/pi-coding-agent` comment.

## Building locally

```bash
docker build -t pi-agent:local .
docker build -t pi-agent:local --build-arg PI_VERSION=1.5.0 .   # override the version
docker run --rm pi-agent:local --version
```

## License

[MIT](LICENSE) for this repo's files. Pi is MIT licensed by its authors; the base image
and Debian packages carry their own licenses (see the image SBOM).
