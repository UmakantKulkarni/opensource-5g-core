# ZTX Helm Integration Changes

Use this document as the implementation checklist for adding ZTX to an existing Helm chart. It only covers the chart changes required to integrate ZTX. Each step links to the exact example lines in this repository.

## 1. Add a top-level ZTX block to values.yaml

Copy the exact ZTX block from [helm-chart/values.yaml](../helm-chart/values.yaml#L18-L57) into the top level of your chart `values.yaml`:

```yaml
ztx:
  enabled: true
  authentication: true
  encryption: true
  tcp: true
  udp: true
  sctp: true
  name: "ztx"
  logLevel: 1
  keyLength: 256
  mtlsKeyLength: 2048
  promPort: 62951 # Should not be 9090
  controllerSvc: "ztx-controller"
  image:
    repository: umakantk/ztx
    pullPolicy: Always
    tag: "ztx_demo_aug"
    initTag: "init"
    controllerTag: "ztx_demo_aug"
  health:
    port: 8080
    nodePort: 32080
  caServer:
    image:
      repository: umakantk/ztx
      pullPolicy: Always
      tag: "ca"
    host: "ztx-controller"
    port: 29615
    bootstrapPort: 29651
    certTTLHours: 240
    caCertPassword: "ztxCaCertPassword"
    authToken: "ztxAuthToken"
  imagePullSecret:
    enabled: true
    name: ztx-private-registry
    server: index.docker.io
    username: token
    password: ""
```

Required settings:

- Keep the `ztx` block at the top level of `values.yaml`.
- Set `ztx.sctp: false` if you want to disable security on the SCTP path between gNodeB and the core.
- Set `ztx.udp: false` if you want to disable security on the PFCP path between SMF and UPF.
- For ZTX images, set username and password as sent in the email.

## 2. Copy the ZTX templates into your chart

Copy these files into your chart `templates/` directory:

- [helm-chart/templates/ztx-sidecar.yaml](../helm-chart/templates/ztx-sidecar.yaml#L1-L121)
- [helm-chart/templates/ztx-controller.yaml](../helm-chart/templates/ztx-controller.yaml#L1-L174)
- [helm-chart/templates/ztx-registry-secret.yaml](../helm-chart/templates/ztx-registry-secret.yaml#L1-L11)

These files provide:

- the shared ZTX sidecar and init-container helpers
- the ZTX controller and CA server deployment
- the private registry secret for ZTX images


## 3. Inject ZTX into every workload you want to protect

For every protected Deployment or StatefulSet, add the ZTX init container before `containers:` and add the ZTX sidecar inside `containers:`.

Examples in this repository:

- init-container include in [helm-chart/templates/amf-deploy.yaml](../helm-chart/templates/amf-deploy.yaml#L73) and [helm-chart/templates/upf-deploy.yaml](../helm-chart/templates/upf-deploy.yaml#L59)
- sidecar include in [helm-chart/templates/amf-deploy.yaml](../helm-chart/templates/amf-deploy.yaml#L76) and [helm-chart/templates/upf-deploy.yaml](../helm-chart/templates/upf-deploy.yaml#L62)


```yaml
spec:
  template:
    spec:
      {{- include "ztxInitContainer" . | nindent 6 }}
      serviceAccountName: <your-service-account>
      containers:
        {{- include "ztxAppTemplate" . | nindent 8 }}
        - name: <your-core-container>
          image: ...
```

Apply this to the workloads that need protection. Inject ZTX into any additional control-plane, or database workloads where you want ZTX to protect TCP, UDP or SCTP traffic.

Required adjustment if your pod already has `imagePullSecrets`:

- Merge the ZTX registry secret into the existing `imagePullSecrets` list.
- Remove the `{{- include "ztxImagePullSecrets" . }}` line shown in [helm-chart/templates/ztx-sidecar.yaml](../helm-chart/templates/ztx-sidecar.yaml#L40) so the pod spec does not render duplicate `imagePullSecrets` keys.
- The helper that adds the ZTX registry secret is defined in [helm-chart/templates/ztx-sidecar.yaml](../helm-chart/templates/ztx-sidecar.yaml#L14-L18).

## 4. Add service account permissions

The service account used by ZTX-enabled pods must be able to read services, endpoints, and pods. The exact example in this repository is [helm-chart/templates/open5gs-role.yaml](../helm-chart/templates/open5gs-role.yaml#L1-L27).

If your chart already has a service account, keep using it and bind equivalent permissions:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <your-service-account>
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ztx-service-reader
rules:
  - apiGroups: [""]
    resources: ["endpoints", "services", "pods"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ztx-service-reader-binding
subjects:
  - kind: ServiceAccount
    name: <your-service-account>
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ztx-service-reader
```

## 5. Completion checklist

Your chart integration is complete when all of the following are true:

1. `values.yaml` contains the top-level `ztx` block.
2. `templates/` contains `ztx-sidecar.yaml`, `ztx-controller.yaml`, and `ztx-registry-secret.yaml`.
3. Every workload that should be protected includes both `ztxInitContainer` and `ztxAppTemplate`.
4. The service account used by ZTX-enabled pods has read access to services, endpoints, and pods.

For optional monitoring, platform caveats, and post-deployment validation, see [ztx-operational-notes.md](ztx-operational-notes.md).
