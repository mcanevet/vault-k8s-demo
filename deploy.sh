#!/bin/bash -e

OLM_VERSION=0.13.0
ARGOCD_OPERATOR_VERSION=0.0.3

echo Deploy Operator Lifecycle Manager
echo
echo Create OLM CRDs
curl -L -s https://github.com/operator-framework/operator-lifecycle-manager/releases/download/$OLM_VERSION/crds.yaml -o olm/crds.yaml
kubectl apply -f olm/crds.yaml
echo
echo Deploy OLM
curl -L -s https://github.com/operator-framework/operator-lifecycle-manager/releases/download/$OLM_VERSION/olm.yaml -o olm/olm.yaml
kubectl apply -f olm/olm.yaml

while [[ $(kubectl get pods -n olm -l app=catalog-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
	echo "waiting for pod catalog-operator" && sleep 5;
done

while [[ $(kubectl get pods -n olm -l app=olm-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
	echo "waiting for pod olm-operator" && sleep 5;
done

echo
echo Deploy ArgoCD Operator using OLM catalog
echo
echo Create argocd namespace
kubectl apply -f apps/templates/namespaces.yaml

echo
echo Create a CatalogSource in the olm namespace
curl -s https://raw.githubusercontent.com/argoproj-labs/argocd-operator/v$ARGOCD_OPERATOR_VERSION/deploy/catalog_source.yaml -o olm/argocd-catalogsource.yaml
kubectl apply -n olm -f olm/argocd-catalogsource.yaml

while [[ $(kubectl get pods -n olm -l olm.catalogSource=argocd-catalog -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
	echo "waiting for pod argocd-catalog" && sleep 5;
done

echo
echo Create an OperatorGroup in the argocd namespace
curl -s https://raw.githubusercontent.com/argoproj-labs/argocd-operator/v$ARGOCD_OPERATOR_VERSION/deploy/operator_group.yaml -o argocd/operatorgroup.yaml
kubectl apply -n argocd -f argocd/operatorgroup.yaml

while [[ $(kubectl get operatorgroups -n argocd argocd-operator -oname) != "operatorgroup.operators.coreos.com/argocd-operator" ]]; do
	echo "waiting for operatorgroup argocd-operator" && sleep 5;
done

# Somehow we have to wait...
sleep 15

echo
echo Create a new Subscription for the Argo CD Operator
curl -s https://raw.githubusercontent.com/argoproj-labs/argocd-operator/v$ARGOCD_OPERATOR_VERSION/deploy/subscription.yaml -o argocd/subscription.yaml
kubectl apply -n argocd -f argocd/subscription.yaml

while [[ $(kubectl get subscriptions -n argocd argocd-operator -o name) != "subscription.operators.coreos.com/argocd-operator" ]]; do
	echo "waiting for subscription argocd-operator" && sleep 5;
done

while [[ $(kubectl get pods -n argocd -l name=argocd-operator -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
	echo "waiting for pod argocd-operator" && sleep 5;
done

echo
echo Deploy ArgoCD
kubectl apply -f argocd/argocd.yaml

while [[ $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
	echo "waiting for pod argocd-server" && sleep 5;
done

echo
echo Deploy app of apps
helm template apps -x templates/apps.yaml | kubectl apply -f -

echo
echo ArgoCD up and running
echo admin password: $(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
echo
echo Use port-forward to access the web ui
echo $ kubectl -n argocd port-forward svc/argocd-server 8080:80
