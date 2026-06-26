# Valkey Helm Chart Tasks

# Run helm-unittest tests
test:
    @echo "=== Running Unit Tests ==="
    helm unittest ./valkey

# Lint the Helm chart
lint:
    @echo "=== Linting Valkey Helm Chart ==="
    helm lint ./valkey

# Render templates with default values
template:
    helm template valkey ./valkey

# Render templates with auth enabled
template-auth:
    helm template valkey ./valkey \
        --set auth.enabled=true \
        --set auth.generateDefaultUser.enabled=true

# Package the chart
package:
    helm package ./valkey

# Run all validations
validate: lint test
    @echo "=== All validations passed ==="

# ---------------------------------------------------------------------------
# End-to-end (live cluster) testing
#
# Layer 2: `helm test` smoke. Standalone — installs Valkey with auth enabled
# onto a real kind cluster and runs the chart-packaged test hooks via
# `helm test`. No Chainsaw involved. See test/e2e/helm-test/HANDOVER.md.
# ---------------------------------------------------------------------------

# kind cluster name and shared config used by every e2e layer
e2e_cluster := "valkey-e2e"
e2e_kind_config := "test/e2e/kind-config.yaml"
# Release name for the helm-test smoke layer
helm_test_release := "valkey-smoke"
helm_test_namespace := "valkey-smoke"

# Check for e2e prerequisites; print install hints rather than failing cryptically
e2e-tools:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=0
    check() {
      if ! command -v "$1" >/dev/null 2>&1; then
        echo "✗ $1 not found — install: $2"
        missing=1
      else
        echo "✓ $1 ($(command -v "$1"))"
      fi
    }
    check kind     "https://kind.sigs.k8s.io/docs/user/quick-start/#installation  (e.g. 'go install sigs.k8s.io/kind@latest' or 'brew install kind')"
    check kubectl  "https://kubernetes.io/docs/tasks/tools/  (e.g. 'brew install kubectl')"
    check helm     "https://helm.sh/docs/intro/install/  (e.g. 'brew install helm')"
    check chainsaw "https://kyverno.github.io/chainsaw/  (e.g. 'go install github.com/kyverno/chainsaw@latest' or download a release binary) — only needed for the Chainsaw e2e layers"
    if [ "$missing" -ne 0 ]; then
      echo ""
      echo "Some prerequisites are missing (see above). The helm-test layer needs kind, kubectl and helm."
      exit 1
    fi
    echo "All prerequisites present."

# Create the shared multi-node kind cluster (no-op if it already exists)
e2e-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if kind get clusters 2>/dev/null | grep -qx "{{e2e_cluster}}"; then
      echo "kind cluster '{{e2e_cluster}}' already exists — reusing it."
    else
      echo "=== Creating kind cluster '{{e2e_cluster}}' ==="
      kind create cluster --name "{{e2e_cluster}}" --config "{{e2e_kind_config}}"
    fi

# Delete the shared kind cluster
e2e-down:
    #!/usr/bin/env bash
    set -euo pipefail
    if kind get clusters 2>/dev/null | grep -qx "{{e2e_cluster}}"; then
      echo "=== Deleting kind cluster '{{e2e_cluster}}' ==="
      kind delete cluster --name "{{e2e_cluster}}"
    else
      echo "kind cluster '{{e2e_cluster}}' does not exist — nothing to delete."
    fi

# Layer 2 (standalone): install Valkey with auth + run the chart's `helm test` hooks.
# Assumes a cluster is up (run `just e2e-up` first, or use the all-in-one `just e2e`).
# In CI the cluster is provided by helm/kind-action, so CI calls this target directly.
helm-test:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=== Layer 2: helm test smoke ==="
    helm dependency build valkey
    helm upgrade --install "{{helm_test_release}}" ./valkey \
      --namespace "{{helm_test_namespace}}" --create-namespace \
      --values test/e2e/helm-test/values.yaml \
      --wait --timeout 5m
    echo "=== Running chart test hooks: helm test {{helm_test_release}} ==="
    helm test "{{helm_test_release}}" --namespace "{{helm_test_namespace}}" --logs

