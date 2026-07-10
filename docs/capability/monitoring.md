

```sh
kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl -n monitoring get secret prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo

https://grafana.arguswatcher.net

kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# then browse to http://localhost:3000

```