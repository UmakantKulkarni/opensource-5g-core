# ZTX Operational Notes

This document supplements the integration guide with optional monitoring, platform dependencies, and post-deployment validation.

## Chart customizations

These points are only relevant if you customize the copied ZTX templates or values.


- If your environment does not use `LoadBalancer`, change the external controller service in [helm-chart/templates/ztx-controller.yaml](../helm-chart/templates/ztx-controller.yaml#L46-L59) to the service type you use.
- If you change `ztx.promPort`, `ztx.health.port`, `ztx.caServer.port`, or `ztx.caServer.bootstrapPort`, update the hard-coded TCP exclusion list in [helm-chart/templates/ztx-sidecar.yaml](../helm-chart/templates/ztx-sidecar.yaml#L1-L2) so ZTX does not intercept its own controller, CA, or metrics traffic.

## Optional monitoring

Monitoring is not required for ZTX to function, but you can add it if you want observability.

- Add a Prometheus scrape target for the ZTX controller metrics endpoint.
- Add Prometheus discovery for ZTX sidecar metrics by matching the ZTX container name.
- Add a Grafana dashboard for ZTX metrics if you want dashboards.

## Platform dependencies and caveats

- The ZTX init container requires `NET_ADMIN` so it can install `iptables` rules.
- The ZTX sidecar requires `NET_ADMIN` and `NET_RAW`.
- Your cluster security policy must allow those Linux capabilities.
- Worker nodes must support `iptables` in the `mangle` table and `NFQUEUE`.
- If `ztx.sctp` is enabled, the nodes and cluster networking stack must support SCTP.
- If your pods already use a service mesh or another traffic-capture sidecar, validate the interaction because both systems may modify pod networking and `iptables` behavior.
- If your chart spans multiple namespaces, use a fully qualified controller service name or keep the controller and protected workloads in the same namespace.

## Post-deployment validation

After integrating ZTX, verify the following:

1. `helm template` renders the controller resources, sidecar injections, and registry secret when enabled.
2. The controller pod becomes Ready, and the controller health endpoint returns HTTP 200.
3. Each protected pod contains both `ztx-init` and `ztx` in addition to the original application container.
4. Pods start without capability or admission-policy errors.
5. Setting `ztx.sctp: false` disables ZTX processing on the gNodeB to core SCTP path.
6. Setting `ztx.udp: false` disables ZTX processing on the SMF to UPF PFCP path.
7. If monitoring is enabled, sidecars expose metrics on `ztx.promPort` and Prometheus can scrape them.