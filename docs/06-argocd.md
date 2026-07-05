# ArgoCD

goal

- ArgoCD manages all in-cluster workloads via GitOps
- app-of-apps: one root `Application`
- install add-ons and votting app

---

## repo layout

```
argocd/
├─ 01-root.yaml          # app-of-apps entry point
└─ apps/
```

---

## delivery phases

| #    | phase               | description                                                                        |
| ---- | ------------------- | ---------------------------------------------------------------------------------- |
| 7.1  | bootstrap root      | create app-of-apps                                                                 |
| 7.2  | install ESO         | deploy eso via helm;                                                               |
| 7.3  | test eso            | add sample `aws secret` via terraform; verify the sample secret in cluster via ESO |
| 7.4  | albc                | install albc                                                                       |
| 7.5  | TG binding          | create ssm parameter to store TG arn; `TargetGroupBinding` reference via ESO       |
| 7.6  | karpenter           | configure karpenter in TF codes; install karpenter via helm                        |
| 7.7  | configure node pool | create node pool; test pod schedules by a sample pod                               |
| 7.8  | voting-app          | update the app values; deploy in cluster                                           |
| 7.9  | expose traffic http | adjust tf and gateway configure to expose http traffic                             |
| 7.10 | install cert-manger | install add-on via tf                                                              |
| 7.11 | enable tls          | expose https traffic                                                               |
| 7.12 | install e-dns       | isntall e-dns via helm                                                             |
| 7.13 | configure e-dns     | confirure e-dns and enable dns via cloudflare;                                     |

---


## Development

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo

kubectl apply -f argocd/00-root.yaml

kubectl -n argocd patch app/00-root -p '{"metadata":{"finalizers":[]}}' --type merge
```