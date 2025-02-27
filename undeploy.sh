#!/bin/bash

readonly OPERATOR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/operator.yaml"
readonly TP_CR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/tp.yaml"

read -p "Before you undeploy the transparent proxy, make sure the resources are no longer needed. This action also permanently removes the sap-transp-proxy-system namespace, service instances, and service bindings created by the transparent proxy. Are you sure you want to continue? (y/n): " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]') 
if [[ "$confirm" == "y" || "$confirm" == "yes" ]]; then
	kubectl delete -f $TP_CR_FILE
	kubectl delete -f $OPERATOR_FILE
else
	echo "Undeploy cancelled."
fi
