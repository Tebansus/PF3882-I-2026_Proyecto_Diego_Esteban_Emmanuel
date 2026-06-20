# Final Project Report — Managing and Securing Microservices with Istio

This report walks through the [Project Proposal](ProjectProposal.md) roadmap and
documents what was actually built and verified for each milestone, with pointers to the
scripts, manifests, and screenshots that back each claim.

## Week 1–2: Local Infrastructure & Baseline Deployment

**Delivered.** A `kind` cluster (`kind-config.yaml`) is created by
[`scripts/01-create-cluster.sh`](../scripts/01-create-cluster.sh), and the Bookinfo
sample application (`productpage`, `details`, `reviews` v1/v2/v3, `ratings`) is deployed
by [`scripts/03-deploy-bookinfo.sh`](../scripts/03-deploy-bookinfo.sh) from
`platform/kube/bookinfo.yaml`. [`scripts/05-validate.sh`](../scripts/05-validate.sh)
confirms the deployment is reachable and renders `details`, `reviews`, and the
`productpage` title before the mesh is introduced.

## Week 3–4: Mesh Installation & Observability

**Delivered.** [`scripts/02-install-istio.sh`](../scripts/02-install-istio.sh) installs
the Istio control plane (`demo-profile-no-gateways.yaml`) and enables sidecar injection
for the `bookinfo` namespace. Kiali, Grafana, and Jaeger are installed by
[`scripts/06-install-metrics.sh`](../scripts/06-install-metrics.sh) and
[`scripts/07-install-tracing.sh`](../scripts/07-install-tracing.sh). Full detail,
including the Kiali service-graph capture and a Jaeger waterfall trace confirming
request propagation across all four Bookinfo services, is in
[Observability.md](Observability.md).

## Week 5–6: Advanced Traffic Engineering

**Delivered.** Canary releases (90/5/5 across `reviews` v1/v2/v3) and header-based
routing (`end-user: jason` → `reviews:v2`) are implemented purely through
`VirtualService`/`DestinationRule` resources in `networking/`, with no application code
changes. See [TrafficEngineering.md](TrafficEngineering.md) for the full rule set, the
load-generator-driven validation (`scripts/10-verify-canary.sh`,
`scripts/11-test-header-routing.sh`), and live Kiali/Grafana captures of the canary
split in `screenshots/routing/`.

## Week 7–8: Resiliency & Fault Injection

**Delivered.** Implemented and verified in [FaultInjection.md](FaultInjection.md):

- Header-targeted 100 % latency injection (7 s delay on `ratings` for `jason`)
- Percentage-based latency injection (50 % of all `ratings` traffic), with a
  latency-distribution measurement script (`scripts/14-test-percentage-fault.sh`) that
  logs every request's elapsed time to `logs/14-latency-fault-percentage.csv` and
  asserts the observed delay rate is within ±15 % of the configured 50 %
- Abort injection (HTTP 500 for `jason`)
- A 3 s timeout / 3-retry policy on `reviews` so `productpage` degrades gracefully
  instead of hanging
- A circuit breaker on `ratings` (max 1 connection, max 1 pending request, ejection
  after 1 consecutive 5xx), validated under `fortio` load with `scripts/16-test-circuit-breaker.sh`

Each scenario has a paired Kiali (service-graph impact) and Grafana (traffic/error
panel) screenshot in `screenshots/fault-injection/`.

## Week 9–10: Zero-Trust Security & Final Delivery

**Delivered.** Implemented and verified in [SecurityPolicies.md](SecurityPolicies.md):

- Namespace-wide strict mTLS (`PeerAuthentication`), validated both for in-mesh
  traffic (`scripts/17-test-mtls.sh`) and for ingress traffic from outside the mesh
  (`scripts/18-test-external-mtls.sh`)
- A deny-all-by-default `AuthorizationPolicy` baseline with four granular `ALLOW`
  rules — `ingress → productpage`, `productpage → details`, `productpage → reviews`,
  `reviews → ratings` — validated with identity-impersonating test clients in
  `scripts/19-test-authz-policies.sh`, confirming both the allowed paths (200) and the
  blocked paths (`ratings → reviews`, `productpage → ratings`, `details → reviews`, all
  403)
- A reference ingress-gateway rate-limiting `EnvoyFilter` configuration
  (`policy/productpage_envoy_ratelimit.yaml`)

### Final delivery checklist (per the proposal's closing paragraph)

| Deliverable | Location |
|---|---|
| Setup scripts | [`scripts/`](../scripts/) (`run-all.sh` runs the entire flow end to end) |
| Screenshots from Kiali (service graph) | `screenshots/routing/`, `screenshots/fault-injection/`, `screenshots/security/` |
| Grafana dashboards | `screenshots/routing/`, `screenshots/fault-injection/` |
| Examples of routing | [TrafficEngineering.md](TrafficEngineering.md) |
| Examples of fault injection | [FaultInjection.md](FaultInjection.md) |
| Examples of security policies | [SecurityPolicies.md](SecurityPolicies.md) |

## Deviations from the original proposal

- **Rate limiting.** The `EnvoyFilter` rate-limit configuration
  (`policy/productpage_envoy_ratelimit.yaml`) is included as reference configuration
  for ingress throttling but, unlike the other security controls, was not part of the
  original Week 9–10 plan and assumes an external Envoy `RateLimitService` that is not
  deployed by `run-all.sh`.
