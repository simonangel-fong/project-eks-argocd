

Smoke tests run automatically on every sync.
```sh
kubectl logs -n voting -l app.kubernetes.io/component=test --tail=200 -f
# or
kubectl get jobs -n voting
kubectl describe job -n voting voting-app-api-smoke-internal
```