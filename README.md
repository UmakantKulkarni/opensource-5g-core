## Opensource 5G Core

Fork opensource-5g-core-service-mesh from bitbucket - https://bitbucket.org/infinitydon/opensource-5g-core-service-mesh/src/main/

This repo contains the code templates that was used in the Opensource 5G core.

## Monitoring

Prometheus, Grafana and a Log Viewer are included in the Helm chart. Grafana can
be enabled or disabled using `monitoring.grafana.enabled` while the log viewer
is controlled by `monitoring.logviewer.enabled` in `values.yaml`. Their
corresponding NodePort values can be adjusted via
`monitoring.grafana.nodeport` and `monitoring.logviewer.nodeport`.

