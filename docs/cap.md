

## Compute-karpenter

```sh

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-test
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: karpenter-test
  template:
    metadata:
      labels:
        app: karpenter-test
    spec:
      nodeSelector:
        workload-class: general
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources:
            requests:
              cpu: "1"
              memory: "1Gi"
EOF

kubectl get nodeclaims -w
# NAME            TYPE        CAPACITY    ZONE            NODE   READY     AGE
# general-87ww5   m5a.large   on-demand   ca-central-1d          Unknown   7s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   Unknown   23s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   Unknown   24s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   Unknown   35s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   Unknown   35s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   True      36s
# general-87ww5   m5a.large   on-demand   ca-central-1d   ip-10-0-12-31.ca-central-1.compute.internal   True      65s

kubectl delete deployment karpenter-test
```