import json
import logging
import os
import subprocess
import time

import pykube
import pytest
from pytest_helm_charts.clusters import Cluster

logger = logging.getLogger(__name__)

# The bundle deploys into the ats release namespace; on a GitOps engine leg ats
# suffixes it with the engine (e.g. agentic-platform-flux).
NAMESPACE = os.environ.get("ATS_RELEASE_NAMESPACE", "agentic-platform")

# Components the meta-package renders as Flux HelmReleases under the trimmed
# tests/test-values.yaml. Kept in sync with `make verify-meta`.
EXPECTED_COMPONENTS = {"muster", "agentic-platform-connectivity"}

# The bundle assertions only make sense on the Flux engine leg, where ats has
# installed Flux and reconciled the rendered CRs. On a plain Helm run there are
# no Flux CRs, so skip rather than fail.
flux_leg_only = pytest.mark.skipif(
    os.environ.get("ATS_EXTRA_GITOPS_ENGINE") != "flux",
    reason="bundle assertions apply only on the Flux GitOps engine leg",
)


def _kubectl_get(resource: str) -> list:
    result = subprocess.run(
        ["kubectl", f"--kubeconfig={os.environ['KUBECONFIG']}", "get", resource, "-n", NAMESPACE, "-o", "json"],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout).get("items", [])


def _is_ready(obj: dict) -> bool:
    conditions = obj.get("status", {}).get("conditions", [])
    return any(c.get("type") == "Ready" and c.get("status") == "True" for c in conditions)


def _wait_for_ready_deployments(
    kube_client: pykube.HTTPClient, selector: dict, timeout_sec: int = 180
) -> list:
    """Wait until every Deployment matching the label selector has all replicas ready."""
    deadline = time.monotonic() + timeout_sec
    while True:
        deployments = list(
            pykube.Deployment.objects(kube_client).filter(namespace=NAMESPACE).filter(selector=selector)
        )
        if deployments and all((d.obj.get("status", {}).get("readyReplicas", 0) or 0) >= 1 for d in deployments):
            return deployments
        if time.monotonic() >= deadline:
            status = {d.name: d.obj.get("status", {}) for d in deployments}
            raise AssertionError(f"Deployments {selector} in '{NAMESPACE}' not ready after {timeout_sec}s: {status}")
        time.sleep(3)


@pytest.mark.smoke
@pytest.mark.functional
@pytest.mark.upgrade
def test_api_working(kube_cluster: Cluster) -> None:
    """The test cluster is reachable and has at least one node."""
    assert kube_cluster.kube_client is not None
    assert len(pykube.Node.objects(kube_cluster.kube_client)) >= 1


@flux_leg_only
@pytest.mark.smoke
@pytest.mark.functional
@pytest.mark.upgrade
def test_bundle_components_present_and_ready() -> None:
    """The meta-package rendered the expected component HelmReleases and Flux reconciled them.

    Runs in the upgrade scenario too, so it asserts the bundle is healthy both before and
    after the helm upgrade (the stable-to-candidate CR-set transition).
    """
    helm_releases = _kubectl_get("helmreleases.helm.toolkit.fluxcd.io")
    names = {hr["metadata"]["name"] for hr in helm_releases}
    missing = EXPECTED_COMPONENTS - names
    assert not missing, f"expected component HelmReleases missing from '{NAMESPACE}': {missing} (found {names})"

    not_ready = [hr["metadata"]["name"] for hr in helm_releases if not _is_ready(hr)]
    assert not not_ready, f"HelmReleases not Ready in '{NAMESPACE}': {not_ready}"


@flux_leg_only
@pytest.mark.functional
def test_bundle_sources_ready() -> None:
    """Every OCIRepository source the bundle points its components at is Ready."""
    sources = _kubectl_get("ocirepositories.source.toolkit.fluxcd.io")
    assert sources, f"no OCIRepository sources found in '{NAMESPACE}'"

    not_ready = [s["metadata"]["name"] for s in sources if not _is_ready(s)]
    assert not not_ready, f"OCIRepository sources not Ready in '{NAMESPACE}': {not_ready}"


@flux_leg_only
@pytest.mark.smoke
@pytest.mark.functional
@pytest.mark.upgrade
@pytest.mark.flaky(reruns=1, reruns_delay=15)
def test_muster_component_running(kube_cluster: Cluster) -> None:
    """The muster component the bundle deploys is actually running, not just reconciled.

    The Flux HelmRelease reporting Ready means the child chart installed; this asserts the
    workload it produced (the muster Deployment) has all replicas ready. Runs in the upgrade
    scenario too, so the workload is verified before and after the upgrade.
    """
    deployments = _wait_for_ready_deployments(kube_cluster.kube_client, {"app.kubernetes.io/name": "muster"})
    for deployment in deployments:
        assert int(deployment.obj["status"]["readyReplicas"]) == int(deployment.obj["spec"]["replicas"])


@flux_leg_only
@pytest.mark.functional
def test_connectivity_httproute_present() -> None:
    """The connectivity component rendered its Gateway API wiring (an HTTPRoute)."""
    routes = _kubectl_get("httproutes.gateway.networking.k8s.io")
    assert routes, f"connectivity did not create an HTTPRoute in '{NAMESPACE}'"
