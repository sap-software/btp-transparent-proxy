#!/bin/bash

OPERATOR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/operator.yaml"
TP_CR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/tp.yaml"


kubectl delete -f $TP_CR_FILE
kubectl delete -f $OPERATOR_FILE
