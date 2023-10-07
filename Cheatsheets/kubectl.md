# Kubectl Cheatsheet

## Basics

| Command | Description |
|--|--|
| `kubectl config current-context` | check your current env  |

## Operations

###  K8s Operations

| Command | Description |
|--|--|
| `kubectl rollout restart deployment *[DEPLOYMENT]* -n *[NAMESPACE]*` | Restart pods of a deployment  |
| `kubectl logs -n *[NAMESPACE]* *[DEPLOYMENT]* -c *[CONTAINER]*` | Check logs in specific container of a deployment  |
| `kubectl run networkutil -n *[NAMESPACE]* --limits cpu=1,memory=1G --rm -i --tty --image *[IMAGE]* -- /bin/bash` | Spawn a testing pod under specific namespace and execute bash  |
| `kubectl exec -it pod/*[POD]* -n *[NAMESPACE]* -- *[COMMAND]*`| Execute command in specific pod  |
| `kubectl logs -n *[NAMESPACE]* --selector=app=*[APP]* -c *[CONTAINER]* -f `| Follow logs of container of a specific app   |

###  Istio Operations

| Command | Description |
|--|--|
| `kubectl label namespace *[NAMESPACE]* istio-injection=enabled` | Enable istio in namespace by adding istio label |
| `kubectl label namespaces *[NAMESPACE]* istio-injection-` | Disable istio in namespace by removing istio label |