#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

# Configuration
E2E_LOG_DIR=${ARTIFACTS_PATH:-_output/e2e-logs}
mkdir -p "$E2E_LOG_DIR"

echo "=== Starting E2E Tests ==="

# Function to wait for a condition
function wait_for_condition() {
    local cmd=$1
    local expected=$2
    local timeout=${3:-300}
    local start_time=$(date +%s)

    echo "Waiting for: $cmd -> $expected"
    while true; do
        current=$(eval "$cmd")
        if [[ "$current" == "$expected" ]]; then
            echo "Condition met!"
            return 0
        fi

        local current_time=$(date +%s)
        if [[ $((current_time - start_time)) -gt $timeout ]]; then
            echo "Timeout waiting for condition."
            return 1
        fi

        sleep 5
    done
}

export KUBECONFIG=$HOME/.kube/karmada.config

echo "Deploying Example Job..."
kubectl --context karmada-apiserver apply -f docs/deploy/exmaple/.

echo "Waiting for Job to be Running..."
# We expect 1 vcjob to be running.
# Adjust the check based on actual output of `kubectl get vcjob`
# STATUS usually is 'Running'
# We'll retry checking for status 'Running'

wait_for_condition "kubectl --context karmada-apiserver get vcjob mindspore-cpu -o jsonpath='{.status.state.phase}' 2>/dev/null" "Running" 300

echo "Job is Running. Verifying Member Clusters..."

# Check member1
echo "Checking member1..."
PODS_MEMBER1=$(kubectl --context member1 get pods -l app=mindspore-cpu -o jsonpath='{.items[*].status.phase}' --kubeconfig=$HOME/.kube/members.config)
echo "Member1 Pods: $PODS_MEMBER1"

# Check member2
echo "Checking member2..."
PODS_MEMBER2=$(kubectl --context member2 get pods -l app=mindspore-cpu -o jsonpath='{.items[*].status.phase}' --kubeconfig=$HOME/.kube/members.config)
echo "Member2 Pods: $PODS_MEMBER2"

# Simple validation: we expect some pods to be Running.
if [[ "$PODS_MEMBER1" == *"Running"* ]] || [[ "$PODS_MEMBER2" == *"Running"* ]]; then
    echo "SUCCESS: Pods are running in member clusters."
else 
    echo "FAILURE: No running pods found in member clusters."
    echo "Member1 Pods: $(kubectl --context member1 get pods --kubeconfig=$HOME/.kube/members.config)"
    echo "Member2 Pods: $(kubectl --context member2 get pods --kubeconfig=$HOME/.kube/members.config)"
    exit 1
fi

echo "=== E2E Tests Completed Successfully ==="
