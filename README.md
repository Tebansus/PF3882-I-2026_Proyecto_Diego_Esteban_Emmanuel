# PF3882-I-2026_Proyecto_Diego_Esteban_Emmanuel
## Project Introduction: Managing and Securing Microservices with Istio

### Overview
As modern software architecture increasingly relies on distributed microservices, managing the complex network interactions between these individual components becomes a critical challenge. This project explores the deployment, management, and securing of a microservices-based architecture using a local Kubernetes cluster and the Istio service mesh. Using the standard Bookinfo sample application as our starting point.

### Project Objectives and Rationale
The primary goal of this project is to demonstrate how a service mesh can solve the inherent challenges of running distributed systems. By systematically implementing Istio’s core features, the project focuses on four distinct areas of operational excellence:

* Observability: Understanding how traffic flows through a distributed system is notoriously difficult. To solve this, we will integrate tools like Kiali, Grafana, and Jaeger to visualize service topology, monitor metrics, and trace requests\.
* Advanced Traffic Engineering: Traditional load balancing is often insufficient for modern deployment strategies. We will utilize Istio's routing capabilities to perform canary deployments and user-specific  routing, demonstrating how to safely test and release new service versions in a live environment.
* System Resiliency: Microservices must be designed to expect and handle failure. By injecting artificial ;atency and configuring timeouts, retries, and circuit breakers, we will ensure the application handles degrades.
* Security: Securing internal cluster traffic is just as vital as securing the external perimeter. We will enforce strict mutual TLS (mTLS) encryption and granular authorization policies, ensuring that only explicitly permitted services can communicate with one another.
## Week 1–2: Local Infrastructure & Baseline Deployment
A shared Git repository will be created containing bash scripts and a `kind-config.yaml` file to automate the setup of a local Kubernetes cluster using Docker. Once the cluster is running, the official manifests of the Istio Bookinfo sample application will be deployed.

The Bookinfo application consists of a small set of microservices:
- productpage (frontend)
- details
- reviews (v1, v2, v3)
- ratings

The deployment will be validated by exposing the application using `kubectl port-forward` or a simple ingress, allowing navigation of the product page and verification of service interactions before introducing the service mesh.

---

## Week 3–4: Mesh Installation & Observability
The Istio service mesh control plane will be installed on the local Kind cluster, and automatic sidecar injection will be enabled for the namespace containing the Bookinfo application.

An Istio Gateway will be configured to expose the application externally. Observability tools included with Istio will be enabled:
- Kiali for service topology visualization
- Grafana for metrics
- Jaeger for distributed tracing

Traffic flow between services (e.g., productpage → reviews → ratings) will be visualized, and traces will confirm request propagation across services.

---

## Week 5–6: Advanced Traffic Engineering
Traffic routing rules will be implemented using Istio’s VirtualServices and DestinationRules without modifying application code.

A canary deployment scenario will be created using the different versions of the reviews service:
- 90% traffic routed to `reviews:v1`
- 10% traffic routed to `reviews:v2` or `v3`

Additionally, header-based routing will be configured:
- Requests from specific users (e.g., logged-in user "jason") will be routed to a specific version (e.g., `reviews:v2` showing ratings)

Traffic generation will be simulated locally using tools like curl loops or a lightweight load generator to validate routing behavior and populate observability dashboards.

---

## Week 7–8: Resiliency & Fault Injection
Fault injection rules will be applied using Istio to simulate failures:

- Inject artificial latency into the `ratings` service to observe impact on the `reviews` service
- Configure timeouts and retries to ensure the frontend degrades gracefully (e.g., page loads without ratings instead of failing completely)

Circuit breaking policies will be applied using DestinationRules:
- Limit concurrent connections to the `ratings` service
- Simulate failures and verify that traffic is temporarily blocked when thresholds are exceeded

---

## Week 9–10: Zero-Trust Security & Final Delivery
The mesh will be secured by enforcing strict mutual TLS (mTLS) across all Bookinfo services.

Authorization policies will be defined to restrict service-to-service communication:
- Only allow `productpage` to call `reviews`
- Only allow `reviews` to call `ratings`

Verification will include confirming encrypted traffic within the cluster and demonstrating restricted communication paths.

Finally, the project will be documented with:
- Setup scripts
- Screenshots from Kiali (service graph)
- Grafana dashboards
- Examples of routing, fault injection, and security policies