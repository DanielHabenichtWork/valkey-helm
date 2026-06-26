# End-to-end (live cluster) tests

These tests install the charts onto a **real** cluster (kind) and prove a
deployment comes up, serves traffic, and survives pod failure. They are *additive*
to the static checks (`helm template`, `helm lint`, `helm unittest`) — those still
run unchanged in their own workflows.

The design is **three decoupled layers**, ordered cheap → expensive. None depends on
another; each has its own Just target and CI job, and CI runs the *same* Just targets
you run locally (the only difference is that CI's cluster comes from
`helm/kind-action` instead of `just e2e-up`).

| Layer | What it does | Just target | Needs |
|---|---|---|---|
| 1. unit / template | `helm-unittest` + `helm template` + `helm lint`. No cluster. | `just test` / `just lint` | helm |
| 2. `helm test` smoke | kind + `helm install` + `helm test` (runs the chart-packaged auth hook). Self-contained, no Chainsaw. | `just helm-test` | kind, kubectl, helm |
| 3. Chainsaw e2e + failure injection | deploy → readiness `assert` → pod `delete` → recovery `assert` → data-survival, for both charts. | `just e2e-valkey`, `just e2e-operator` | kind, kubectl, helm, chainsaw |

Layer 2 is documented in detail (including how chart *consumers* run it) in
[`helm-test/HANDOVER.md`](helm-test/HANDOVER.md).

## Prerequisites

```sh
just e2e-tools   # checks for kind / kubectl / helm / chainsaw, prints install hints
```

`kind` also needs a running container runtime (Docker/Podman). `chainsaw` is only
needed for layer 3.

## Quick start (all layers, one command)

```sh
just e2e            # kind up -> helm-test -> both Chainsaw suites -> teardown
just e2e keep=1     # same, but leave the cluster up for debugging
```

Teardown runs in a trap, so a failed layer still cleans up (unless `keep=1`).

## Running a single layer

```sh
just e2e-up         # create the shared 4-node kind cluster (no-op if it exists)

just helm-test      # layer 2: install valkey w/ auth + run `helm test`
just e2e-valkey     # layer 3: chart deploy + replica/primary pod-kill recovery
just e2e-operator   # layer 3: operator install + cluster + primary-failure/promotion

just e2e-down       # delete the cluster
```

## Iterating on one suite

```sh
just e2e-debug      # bring the cluster up and leave it running
# edit a test, then rerun just that suite against the kept cluster:
just e2e-valkey
# inspect a failure directly:
kubectl get pods -A
just e2e-down       # when finished
```

## Inspecting failures

The Chainsaw suites have `catch` blocks that, on any step failure, dump pod
descriptions, pod logs, and namespace events — so the cause is in the test output
without extra digging. Chainsaw creates a fresh ephemeral namespace per test and
deletes it on completion; use `just e2e-debug` + rerun if you need to poke at a
cluster mid-failure (re-add the cluster, rerun, then `kubectl` before it cleans up).

## Layout

```
test/e2e/
  kind-config.yaml          # shared 4-node kind config (1 cp + 3 workers)
  helm-test/                # layer 2 (smoke) — see HANDOVER.md
    values.yaml
    HANDOVER.md
  valkey-chart/             # layer 3 — primary/replica chart
    chainsaw-test.yaml
    values.yaml
    assert-ready.yaml
  valkey-operator/          # layer 3 — operator / cluster mode
    chainsaw-test.yaml
    valkeycluster.yaml
    assert-cluster-ready.yaml
.chainsaw.yaml              # Chainsaw config (timeouts) — repo root
```

## CI

[`.github/workflows/e2e.yml`](../../.github/workflows/e2e.yml) runs three independent
jobs — `helm-test`, `valkey-chart`, `valkey-operator` — each calling the matching
Just target. The multi-node kind config and Chainsaw's `delete`/`script` model leave
room to grow into node-drain, network-partition, and upgrade/rollback tests later
without rework.
