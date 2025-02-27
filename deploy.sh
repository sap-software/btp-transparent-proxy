#!/bin/bash

set -euo pipefail

readonly TP_CR_NAME="transparent-proxy"
readonly TP_CR_NAMESPACE="sap-transp-proxy-system"
readonly OPERATOR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/operator.yaml"
readonly TP_CR_FILE_CONTENT=$(curl -s "https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/tp.yaml")

show_usage() {
  echo "Usage: deploy.sh [OPTIONS]"

  echo "Options:"
  echo "### Using a destination service instance key as plain JSON"
  echo "  -dsk,  --destination-service-key <value>          Use a destination service instance key."
  echo "  -dsin, --destination-service-instance-name <value>  Specify the destination service instance name."
  echo ""
  echo "### Using a Kubernetes Secret holding a destination service instance key"
  echo "  -dssn, --destination-service-secret-name <value>  Use a Kubernetes secret holding a destination service instance key."
  echo "  -dssns, --destination-service-secret-namespace <value>  Specify the secret namespace."
  echo "  -dssk, --destination-service-secret-key <value>  Specify the secret key holding the destination service instance key."
  echo "  -dsin, --destination-service-instance-name <value>  (Optional) Specify the service instance name. If not provided, the secret name will be used."
  echo ""
  echo "### Leveraging SAP BTP Service Operator for automatic destination service instance creation"
  echo "  (no options)                                     If BTP operator is present in the Kubernetes cluster, a default destination service instance is created and linked to the transparent proxy."
  echo ""
  echo "Examples:"
  echo "  deploy.sh --destination-service-key my-key-json --destination-service-instance-name my-instance"
  echo "  deploy.sh --destination-service-secret-name my-secret --destination-service-secret-namespace my-namespace --destination-service-secret-key my-key"
  echo "  deploy.sh  # If BTP operator is present in the Kubernetes cluster, a default destination service instance is created and linked to the transparent proxy."
}

print_success() {
  echo "\033[32mOperation successful. To take a look at the transparent proxy configuration, execute:
kubectl get tp $TP_CR_NAME -n $TP_CR_NAMESPACE -o yaml\033[0m" >&2
  exit 0
}

print_error() {
  local message="$1"
  echo "\033[31m$message\033[0m" >&2
  exit 1
}

get_instance_index() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return 1
  fi

  resource_yaml="$(kubectl get tp $TP_CR_NAME -n $TP_CR_NAMESPACE -o yaml)"

  in_instances=0
  in_associate_with=0
  index=0

  while IFS= read -r line; do

    trimmed_line=$(echo "$line" | sed 's/^[ \t]*//')
    if [[ "$trimmed_line" == "instances:" ]]; then
      in_instances=1
      continue
    fi

    if [[ "$trimmed_line" == "- associateWith:" ]]; then
      in_associate_with=1
      continue
    fi

    if [[ $in_instances -eq 1 && in_associate_with -eq 0 && "$trimmed_line" =~ ^[a-zA-Z0-9_-]+: && ! "$trimmed_line" == "serviceCredentials:" && ! "$trimmed_line" == "secret"*  ]]; then
      break
    fi

    if [[ $in_instances -eq 1 && ( "$trimmed_line" == "- name:"* || "$trimmed_line" == "name:"* ) ]]; then
      found_name=$(echo "$trimmed_line" | cut -d':' -f2 | xargs)
      if [[ "$found_name" == "$instance_name" ]]; then
        echo "$index"
        return 0
      fi

      ((index++))
    fi
  done <<< "$resource_yaml"

  echo "-1"  
  return 1 
}

replace_destination_service_instance() {
  local instance_name="$1"
  local secret_key="$2"
  local secret_name="$3"
  local secret_namespace="$4"
  local instance_index="$5"

  if [[ -z "$instance_name" || -z "$secret_key" || -z "$secret_name" || -z "$secret_namespace" ]]; then
    return 1
  fi

  kubectl patch tp $TP_CR_NAME -n $TP_CR_NAMESPACE --type='json' -p="$(cat <<EOF
[
  {
    "op": "replace",
    "path": "/spec/config/integration/destinationService/instances/$instance_index",
    "value": {
      "name": "${instance_name}",
      "serviceCredentials": {
        "secretKey": "${secret_key}",
        "secretName": "${secret_name}",
        "secretNamespace": "${secret_namespace}"
      }
    }
  }
]
EOF
)"

  return $?
}


add_destination_service_instance() {
  local instance_name="$1"
  local secret_key="$2"
  local secret_name="$3"
  local secret_namespace="$4"



  kubectl patch tp $TP_CR_NAME -n $TP_CR_NAMESPACE --type='json' -p="$(cat <<EOF
[
  {
    "op": "add",
    "path": "/spec/config/integration/destinationService/instances/-",
    "value": {
      "name": "${instance_name}",
      "serviceCredentials": {
        "secretKey": "${secret_key}",
        "secretName": "${secret_name}",
        "secretNamespace": "${secret_namespace}"
      }
    }
  }
]
EOF
)"
}

update_k8s_secret() {
  local secret_name="$1"
  local secret_namespace="$2"
  local new_json="$3"

  if [[ -z "$secret_name" || -z "$secret_namespace" || -z "$new_json" ]]; then
    return 1
  fi

  new_encoded_value=$(echo "$new_json" | base64 | tr -d '\n')

  kubectl patch secret "$secret_name" -n "$secret_namespace" --type='merge' -p "{\"data\": {\"defaultKey\": \"$new_encoded_value\"}}" >/dev/null 2>&1
  return $?
}

DS_KEY_JSON=""
DS_SECRET_NAME=""
DS_SECRET_NAMESPACE=""
DS_SECRET_KEY=""
DS_INSTANCE_NAME=""

PARAMS_PASSED=$#

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      show_usage
      exit 0
      ;;
    --destination-service-key|-dsk)
      if [[ -n "$2" && "$2" != -* ]]; then
        DS_KEY_JSON="$2"
        shift 2
      else
        print_error "Missing value for $1"
        exit 1
      fi
      ;;
    --destination-service-secret-name|-dssn)
      if [[ -n "$2" && "$2" != -* ]]; then
        DS_SECRET_NAME="$2"
        shift 2
      else
        print_error "Missing value for $1"
        exit 1
      fi
      ;;
    --destination-service-secret-namespace|-dssns)
      if [[ -n "$2" && "$2" != -* ]]; then
        DS_SECRET_NAMESPACE="$2"
        shift 2
      else
        print_error "Missing value for $1"
        exit 1
      fi
      ;;
    --destination-service-secret-key|-dssk)
      if [[ -n "$2" && "$2" != -* ]]; then
        DS_SECRET_KEY="$2"
        shift 2
      else
        print_error "Missing value for $1"
        exit 1
      fi
      ;;
    --destination-service-instance-name|-dsin)
      if [[ -n "$2" && "$2" != -* ]]; then
        DS_INSTANCE_NAME="$2"
        shift 2
      else
        print_error "Missing value for $1"
        exit 1
      fi
      ;;
    *)
      print_error "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

BTP_OPERATOR_PRESENT=false
if [[ $PARAMS_PASSED -eq 0 ]]; then
  echo "No arguments provided. Checking whether BTP Operator is present in the cluster..."
  CRD_NAME="serviceinstances.services.cloud.sap.com"
  set +e
  kubectl get crd $CRD_NAME &> /dev/null
  exit_status=$?
  set -e

  if [ $exit_status -eq 0 ]; then
      echo "BTP Operator is present. A default destination service instance with name 'sap-transp-proxy-default' will be created."
      BTP_OPERATOR_PRESENT=true
  else
    print_error "No BTP Operator is present. Invalid operation."
    show_usage  
    exit 1
  fi
fi

if [[ (-n "$DS_KEY_JSON" && -n "$DS_SECRET_NAME" && -n "$DS_SECRET_NAMESPACE" && -n "$DS_SECRET_KEY")
	|| (-n "$DS_KEY_JSON" && ( -n "$DS_SECRET_NAME" || -n "$DS_SECRET_NAMESPACE" || -n "$DS_SECRET_KEY" )) 
  || (-n "$DS_KEY_JSON" && -z "$DS_INSTANCE_NAME")
  || ( -n "$DS_SECRET_NAME" || -n "$DS_SECRET_NAMESPACE" || -n "$DS_SECRET_KEY" ) && ( -z "$DS_SECRET_NAME" || -z "$DS_SECRET_NAMESPACE" || -z "$DS_SECRET_KEY" ) ]]; then
  print_error "Invalid operation."
  show_usage 
  exit 1
fi

if [[ -n "$DS_SECRET_NAME" && -n "$DS_SECRET_NAMESPACE" && -n "$DS_SECRET_KEY" ]]; then
  if [[ -z "$DS_INSTANCE_NAME" ]]; then
    DS_INSTANCE_NAME=$DS_SECRET_NAME
  fi

  set +e
  SECRET_DATA=$(kubectl get secret $DS_SECRET_NAME -n $DS_SECRET_NAMESPACE -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}' 2>&1 )
  exit_status=$?
  set -e
 
  if [ $exit_status -ne 0 ]; then    
    print_error "Failed to find an existing secret with name [$DS_SECRET_NAME] in namespace [$DS_SECRET_NAMESPACE] for destination service instance [$DS_INSTANCE_NAME]."
  elif ! echo "$SECRET_DATA" | grep -q "^$DS_SECRET_KEY$"; then
    print_error "Failed to find key [$DS_SECRET_KEY] in the existing secret for destination service instance [$DS_INSTANCE_NAME]."
  fi

  kubectl apply -f $OPERATOR_FILE

  set +e
  output=$(kubectl get tp $TP_CR_NAME -n $TP_CR_NAMESPACE 2>&1)
  exit_status=$?
  set -e

  output=$(echo "$output" | grep -v "EXIT_CODE:")
  if [[ $exit_status -ne 0  && $output == *"NotFound"* ]]; then
    echo "$TP_CR_FILE_CONTENT" | SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY=$DS_SECRET_KEY envsubst | kubectl create -f - >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "The Transparent Proxy custom resource has been created."
      print_success
    fi
  fi
  
  set +e
  DS_INSTANCE_INDEX=$(get_instance_index $DS_INSTANCE_NAME 2>&1)
  exit_status=$?
  set -e

  if (( $DS_INSTANCE_INDEX >= 0 )); then
    read -p "An existing instance configuration with the name [$DS_INSTANCE_NAME] has been found. The instance configuration in Transparent Proxy custom resource will be updated with the provided Kubernetes secret, which may affect applications that depend on the instance. Do you want to proceed with the update? [y/n]: " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
      echo "Destination service instance configuration [$DS_INSTANCE_NAME] has not been updated in the Transparent Proxy custom resource."
      exit 0
    fi
    set +e
    replace_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE $DS_INSTANCE_INDEX
    exit_status=$?
    set -e
    if [[ $exit_status -eq 0 ]]; then
      echo "Destination service instance [$DS_INSTANCE_NAME] has been successfully replaced."
      print_success
    else
      print_error "Failed to replace destination service instance [$DS_INSTANCE_NAME]."
    fi
  else
    set +e
    add_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE 2>&1
    exit_status=$?
    set -e
    
    if [ $exit_status -eq 0 ]; then
      echo "Destination service instance configuration [$DS_INSTANCE_NAME] has been added successfully to the Transparent Proxy custom resource."
      print_success
    else
      print_error "The destination service instance configuration [$DS_INSTANCE_NAME] could not be added to the Transparent Proxy custom resource."
    fi
  fi
  exit 0
fi

if [[ -n "$DS_KEY_JSON" ]]; then
  kubectl apply -f $OPERATOR_FILE

  DS_SECRET_NAME=$DS_INSTANCE_NAME
  DS_SECRET_NAMESPACE=$TP_CR_NAMESPACE
  DS_SECRET_KEY="defaultKey"
  
  set +e
  output=$(kubectl get secret $DS_SECRET_NAME -n $DS_SECRET_NAMESPACE 2>&1)
  exit_status=$?
  set -e

  output=$(echo "$output" | grep -v "EXIT_CODE:")
  if [[ $exit_status -ne 0  && $output == *"NotFound"* ]]; then
      kubectl create secret generic $DS_SECRET_NAME --from-literal=$DS_SECRET_KEY="$DS_KEY_JSON" -n $DS_SECRET_NAMESPACE >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has been created."
      else
        print_error "Failed to create Kubernetes secret for destination service instance [$DS_INSTANCE_NAME]."
      fi
  fi

  set +e
  output=$(kubectl get tp $TP_CR_NAME -n $TP_CR_NAMESPACE 2>&1)
  exit_status=$?
  set -e

  output=$(echo "$output" | grep -v "EXIT_CODE:")
  if [[ $exit_status -ne 0  && $output == *"NotFound"* ]]; then
    echo "$TP_CR_FILE_CONTENT" | SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY=$DS_SECRET_KEY envsubst | kubectl create -f - >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "The Transparent Proxy custom resource has been created."
      print_success
    fi
  fi

  set +e
  DS_INSTANCE_INDEX=$(get_instance_index $DS_INSTANCE_NAME 2>&1)
  exit_status=$?
  set -e

  if (( $DS_INSTANCE_INDEX >= 0 )); then
      read -p "An existing instance configuration with the name [$DS_INSTANCE_NAME] has been found. The Kubernetes secret named [$DS_SECRET_NAME] will be updated with the provided service key, which may affect other applications that depend on this secret. Do you want to proceed with the update? (y/n): " confirm
      confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]') 
      if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has not been updated in the Transparent Proxy custom resource."
        exit 0
      fi
      set +e
      update_k8s_secret "$DS_SECRET_NAME" "$DS_SECRET_NAMESPACE" "$DS_KEY_JSON"
      exit_status=$?
      set -e
      if [ $exit_status -eq 0 ]; then
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has been updated successfully."
        print_success
      else
        print_error "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] could not be updated."
      fi
  else
      set +e
      add_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE 2>&1
      exit_status=$?
      set -e
     
      if [ $exit_status -eq 0 ]; then
        echo "Destination service instance [$DS_INSTANCE_NAME] has been added successfully to the Transparent Proxy custom resource."
        print_success
      else
        print_error "Destination service instance [$DS_INSTANCE_NAME] could not be added to the Transparent Proxy custom resource."
      fi
  fi
fi

if [[ $BTP_OPERATOR_PRESENT == true ]]; then
  kubectl apply -f $OPERATOR_FILE

  DS_SECRET_NAME="sap-transp-proxy-default"
  DS_SECRET_NAMESPACE=$TP_CR_NAMESPACE
  DS_INSTANCE_NAME=$DS_SECRET_NAME

  set +e
  output=$(kubectl get tp $TP_CR_NAME -n $TP_CR_NAMESPACE 2>&1)
  exit_status=$?
  set -e

  output=$(echo "$output" | grep -v "EXIT_CODE:")
  if [[ $exit_status -ne 0  && $output == *"NotFound"* ]]; then
    echo "$TP_CR_FILE_CONTENT" | SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY="" envsubst | kubectl create -f - >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "The Transparent Proxy custom resource has been created."
      print_success
    fi
  fi

  exit 0
fi
