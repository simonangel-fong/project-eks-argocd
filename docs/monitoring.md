

```sh
# Password
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo

# Username
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-user}' | base64 -d; echo

https://grafana.arguswatcher.net

kubectl -n monitoring port-forward svc/prometheus-grafana 3000:80
# then browse to http://localhost:3000

```