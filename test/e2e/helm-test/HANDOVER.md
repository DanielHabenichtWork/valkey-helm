# `helm test` smoke layer — handover

This directory is a **self-contained** testing layer: kind + `helm install` + `helm test`.
It has **no dependency on Chainsaw** (the failure-injection e2e layer) and nothing
Chainsaw-specific. You can run it, understand it, and hand it off on its own.

## What `helm test` is

`helm test` runs the test hooks that ship *inside* the chart. A chart author marks a
Pod (or Job) with `helm.sh/hook: test`; after a release is installed, `helm test
<release>` creates those Pods in-cluster and reports pass/fail based on their exit
code. Because the tests live in the chart, **any consumer of the chart can run them
against their own install** — they are not CI-only.

For this chart the test hook is the auth check at
[`valkey/templates/tests/auth.yaml`](../../../valkey/templates/tests/auth.yaml). It
only renders when authentication is enabled with at least one inline password, which
is exactly why this layer installs with [`values.yaml`](values.yaml) (auth on +
a `default` user with an inline password). Without those values the hook (and the
`-auth` Secret it reads) wouldn't render and `helm test` would be a no-op.

## Run it

Prerequisites: `kind`, `kubectl`, `helm`. Check with `just e2e-tools`.

```sh
# One step at a time
just e2e-up        # create the shared multi-node kind cluster (no-op if it exists)
just helm-test     # helm install valkey (auth on) + helm test <release>
just e2e-down      # tear the cluster down

# Equivalent raw commands (no Just):
kind create cluster --name valkey-e2e --config test/e2e/kind-config.yaml
helm dependency build valkey
helm upgrade --install valkey-smoke ./valkey \
  --namespace valkey-smoke --create-namespace \
  --values test/e2e/helm-test/values.yaml --wait --timeout 5m
helm test valkey-smoke --namespace valkey-smoke --logs
kind delete cluster --name valkey-e2e
```

A green run prints `✓ PING successful` / `✓ Authentication test passed ...` from the
hook Pod and `helm test` exits 0.

## How a chart *consumer* runs it against their own release

The layer is portable — point it at any release you've installed from this chart:

```sh
# Assuming you installed with auth enabled (inline password) under release "my-valkey":
helm test my-valkey --namespace <your-namespace> --logs
```

If `helm test` reports "no tests found", the release was installed without auth
(or without an inline password), so the auth hook didn't render. Re-install with
auth enabled — see [`values.yaml`](values.yaml) for the minimal config.

## Adding new chart test hooks

Drop another manifest under
[`valkey/templates/tests/`](../../../valkey/templates/tests/) annotated with:

```yaml
metadata:
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
```

It will be picked up automatically by `helm test` — no change needed here or in CI.
Keep these hooks minimal and portable (no Chainsaw, no CI-only assumptions) so chart
consumers can run them too. Deeper failure/recovery orchestration belongs in the
Chainsaw e2e layer, not here.

## CI

CI runs the **same `just helm-test` target** as local. The only difference is who
creates the cluster: `helm/kind-action` in CI vs `just e2e-up` locally. See the
`helm-test` job in [`.github/workflows/e2e.yml`](../../../.github/workflows/e2e.yml).
