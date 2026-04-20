## Opensource 5G Core

Fork opensource-5g-core-service-mesh from bitbucket - https://bitbucket.org/infinitydon/opensource-5g-core-service-mesh/src/main/

This repo contains the code templates that was used in the Opensource 5G core.

## Monitoring

Prometheus, Grafana and a Log Viewer are included in the Helm chart. Grafana can
be enabled or disabled using `monitoring.grafana.enabled` while the log viewer
is controlled by `monitoring.kubernetesui.enabled` in `values.yaml`. Their
corresponding NodePort values can be adjusted via
`monitoring.grafana.nodeport` and `monitoring.kubernetesui.nodeport`.

The optional log forwarder streams container logs to a remote HTTP endpoint.
See `docs/logforwarder.md` for an overview of its architecture and usage.

## Deploy 5G Core using python-based web server:
```
cd webapp
python3 server.py
```

## ZTX images access & citation

For a reusable step-by-step Helm integration guide, see [docs/ztx-integration.md](docs/ztx-integration.md).

If you would like to use this repository and pull ZTX-specific Docker images in your Helm chart, please contact me on LinkedIn (https://www.linkedin.com/in/umakantkulkarni/) and I will grant you access. Accordingly modify values.yaml with these credentials. Also, please cite our paper if you are using these Helm charts for your project. Below is the BibTeX citation details:

```bibtex
@INPROCEEDINGS{10774032,
	author={Kulkarni, Umakant and Fahmy, Sonia},
	booktitle={MILCOM 2024 - 2024 IEEE Military Communications Conference (MILCOM)}, 
	title={Securing the Cloud-Native 5G Control Plane}, 
	year={2024},
	volume={},
	number={},
	pages={1-6},
	keywords={Military communication;Protocols;5G mobile communication;Microservice architectures;Authentication;Complex networks;Zero Trust;Encryption;Resource management},
	doi={10.1109/MILCOM61039.2024.10774032}
}
```
