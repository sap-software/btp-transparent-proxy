#!/bin/bash

get_instance_index() {
  local instance_name="$1"

  if [[ -z "$instance_name" ]]; then
    return 1
  fi

  resource_yaml=$(kubectl get tp transparent-proxy -n sap-transp-proxy-system -o yaml)

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

  kubectl patch tp transparent-proxy -n sap-transp-proxy-system --type='json' -p="
  [
    {
      \"op\": \"replace\",
      \"path\": \"/spec/config/integration/destinationService/instances/$instance_index\",
      \"value\": {
        \"name\": \"${instance_name}\",
        \"serviceCredentials\": {
          \"secretKey\": \"${secret_key}\",
          \"secretName\": \"${secret_name}\",
          \"secretNamespace\": \"${secret_namespace}\"
        }
      }
    }
  ]"

  if [[ $? -eq 0 ]]; then
    echo "Destination service instance: $instance_name is successfully replaced"
  else
    echo "Failed to replace destination service instance."
    return 1
  fi
}


add_destination_service_instance() {
  local instance_name="$1"
  local secret_key="$2"
  local secret_name="$3"
  local secret_namespace="$4"


  kubectl patch tp transparent-proxy -n sap-transp-proxy-system --type='json' -p="
  [
    {
      \"op\": \"add\",
      \"path\": \"/spec/config/integration/destinationService/instances/-\",
      \"value\": {
        \"name\": \"${instance_name}\",
        \"serviceCredentials\": {
          \"secretKey\": \"${secret_key}\",
          \"secretName\": \"${secret_name}\",
          \"secretNamespace\": \"${secret_namespace}\"
        }
      }
    }
  ]"

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

OPERATOR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/operator.yaml"
TP_CR_FILE="https://raw.githubusercontent.com/sap-software/btp-transparent-proxy/refs/heads/main/tp.yaml"

DS_KEY_JSON=""
DS_SECRET_NAME=""
DS_SECRET_NAMESPACE=""
DS_SECRET_KEY=""
DS_INSTANCE_NAME=""

PARAMS_PASSED=$#

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination-service-key|-dsk)
      DS_KEY_JSON="$2"
      shift 2
      ;;
    --destination-service-secret-name|-dssn)
      DS_SECRET_NAME="$2"
      shift 2
      ;;
    --destination-service-secret-namespace|-dssns)
      DS_SECRET_NAMESPACE="$2"
      shift 2
      ;;
    --destination-service-secret-key|-dssk)
      DS_SECRET_KEY="$2"
      shift 2
      ;;
    --destination-service-instance-name|-dsin)
      DS_INSTANCE_NAME="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--destination-service-key|-dsk <value> --destination-service-instance-name|-dsin <value>] |\n[--destination-service-secret-name|-dssn <value> \n --destination-service-secret-namespace|-dssns <value> \n --destination-service-secret-key|-dssk <value> \n [--destination-service-instance-name|-dsin <value>]]"
      exit 1
      ;;
  esac
done

BTP_OPERATOR_PRESENT=false

if [[ $PARAMS_PASSED -eq 0 ]]; then
  echo "No arguments provided. Checking whether BTP Operator is present in the cluster..."
  CRD_NAME="serviceinstances.services.cloud.sap.com"
  kubectl get crd $CRD_NAME &> /dev/null

  if [ $? -eq 0 ]; then
      echo "BTP Operator is present."
      BTP_OPERATOR_PRESENT=true
  else
    echo "No BTP Operator is present. A default destination service instance with name 'sap-transp-proxy-default' will be created."
    echo "You must provide either:"
    echo "  1. --destination-service-key|-dsk <value> \n     and --destination-service-instance-name|-dsin <value> - destination service(DS) key as JSON and destination service(DS) instance name OR"
    echo "  2. --destination-service-secret-name|-dssn <value>, \n     --destination-service-secret-namespace|-dssns <value> \n     and --destination-service-secret-key|-dssk <value>. - Refer destination service(DS) secret from another namespace"
    echo "Usage: $0 [--destination-service-key|-dsk <value> --destination-service-instance-name|-dsin <value>] |\n[--destination-service-secret-name|-dssn <value> \n --destination-service-secret-namespace|-dssns <value> \n --destination-service-secret-key|-dssk <value> \n [--destination-service-instance-name|-dsin <value>]]"
    exit 1
  fi
fi

if [[ (-n "$DS_KEY_JSON" && -n "$DS_SECRET_NAME" && -n "$DS_SECRET_NAMESPACE" && -n "$DS_SECRET_KEY")
	|| (-n "$DS_KEY_JSON" && ( -n "$DS_SECRET_NAME" || -n "$DS_SECRET_NAMESPACE" || -n "$DS_SECRET_KEY" )) 
  || (-n "$DS_KEY_JSON" && -z "$DS_INSTANCE_NAME")
  || ( -n "$DS_SECRET_NAME" || -n "$DS_SECRET_NAMESPACE" || -n "$DS_SECRET_KEY" ) && ( -z "$DS_SECRET_NAME" || -z "$DS_SECRET_NAMESPACE" || -z "$DS_SECRET_KEY" ) ]]; then
  echo "You must provide either:"
  echo "  1. --destination-service-key|-dsk <value> \n     and --destination-service-instance-name|-dsin <value> - destination service(DS) key as JSON and destination service(DS) instance name OR"
  echo "  2. --destination-service-secret-name|-dssn <value>, \n     --destination-service-secret-namespace|-dssns <value> \n     and --destination-service-secret-key|-dssk <value>. - Refer destination service(DS) secret from another namespace"
  echo "Usage: $0 [--destination-service-key|-dsk <value> --destination-service-instance-name|-dsin <value>] |\n[--destination-service-secret-name|-dssn <value> \n --destination-service-secret-namespace|-dssns <value> \n --destination-service-secret-key|-dssk <value> \n [--destination-service-instance-name|-dsin <value>]]"
  exit 1
fi

kubectl apply -f $OPERATOR_FILE

if [[ -n "$DS_SECRET_NAME" && -n "$DS_SECRET_NAMESPACE" && -n "$DS_SECRET_KEY" ]]; then
  if [[ -z "$DS_INSTANCE_NAME" ]]; then
    DS_INSTANCE_NAME=$DS_SECRET_NAME
  fi

  SECRET_DATA=$(kubectl get secret $DS_SECRET_NAME -n $DS_SECRET_NAMESPACE -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}' 2>/dev/null )
  if [ $? -ne 0 ]; then    
    echo "Failed to find an existing secret for destination service instance [$DS_INSTANCE_NAME]."
    exit 1
  elif ! echo "$SECRET_DATA" | grep -q "^$DS_SECRET_KEY$"; then
    echo "Failed to find key [$DS_SECRET_KEY] in the existing secret for destination service instance [$DS_INSTANCE_NAME]."
    exit 1
  fi
  

  SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY=$DS_SECRET_KEY envsubst < $TP_CR_FILE | kubectl create -f - >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "The Transparent Proxy custom resource has been created."
    exit 0
  fi
  DS_INSTANCE_INDEX=$(get_instance_index $DS_INSTANCE_NAME)
  if (( $DS_INSTANCE_INDEX >= 0 )); then
    read -p "An existing instance configuration with the name [$DS_INSTANCE_NAME] has been found. The instance configuration in Transparent Proxy custom resource will be updated with the provided Kubernetes secret, which may affect applications that depend on the instance. Do you want to proceed with the update? [y/n]: " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
      echo "Destination service instance configuration [$DS_INSTANCE_NAME] has not been updated in the Transparent Proxy custom resource."
      exit 0
    fi
    replace_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE $DS_INSTANCE_INDEX
  else
    add_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE
    if [ $? -eq 0 ]; then
      echo "Destination service instance configuration [$DS_INSTANCE_NAME] has been added successfully to the Transparent Proxy custom resource."
    else
      echo "The destination service instance configuration [$DS_INSTANCE_NAME] could not be added to the Transparent Proxy custom resource."
    fi
  fi
  exit 0
fi

if [[ -n "$DS_KEY_JSON" ]]; then
  DS_SECRET_NAME=$DS_INSTANCE_NAME
  DS_SECRET_NAMESPACE="sap-transp-proxy-system"
  DS_SECRET_KEY="defaultKey"
  kubectl get secret $DS_SECRET_NAME -n $DS_SECRET_NAMESPACE >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    kubectl create secret generic $DS_SECRET_NAME --from-literal=$DS_SECRET_KEY="$DS_KEY_JSON" -n $DS_SECRET_NAMESPACE >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has been created."
    else
      echo "Failed to create Kubernetes secret for destination service instance [$DS_INSTANCE_NAME]."
      exit 1
    fi
  fi

  SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY=$DS_SECRET_KEY envsubst < $TP_CR_FILE | kubectl create -f - >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "The Transparent Proxy custom resource has been created."
    exit 0
  fi
  DS_INSTANCE_INDEX=$(get_instance_index $DS_INSTANCE_NAME)
  if (( $DS_INSTANCE_INDEX >= 0 )); then
      read -p "An existing instance configuration with the name [$DS_INSTANCE_NAME] has been found. The Kubernetes secret named [$DS_SECRET_NAME] will be updated with the provided service key, which may affect other applications that depend on this secret. Do you want to proceed with the update? (y/n): " confirm
      confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]') 
      if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has not been updated in the Transparent Proxy custom resource."
        exit 0
      fi
      update_k8s_secret "$DS_SECRET_NAME" "$DS_SECRET_NAMESPACE" "$DS_KEY_JSON"
      if [ $? -eq 0 ]; then
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] has been updated successfully."
      else
        echo "Kubernetes secret for destination service instance [$DS_INSTANCE_NAME] could not be updated."
      fi
  else
      add_destination_service_instance $DS_INSTANCE_NAME $DS_SECRET_KEY $DS_SECRET_NAME $DS_SECRET_NAMESPACE
      if [ $? -eq 0 ]; then
        echo "Destination service instance [$DS_INSTANCE_NAME] has been added successfully to the Transparent Proxy custom resource."
      else
        echo "Destination service instance [$DS_INSTANCE_NAME] could not be added to the Transparent Proxy custom resource."
      fi
  fi
  exit 0
fi

if [[ $BTP_OPERATOR_PRESENT == true ]]; then
  DS_SECRET_NAME="sap-transp-proxy-default"
  DS_SECRET_NAMESPACE="sap-transp-proxy-system"
  DS_INSTANCE_NAME=$DS_SECRET_NAME
  SERVICE_INSTANCE_NAME=$DS_INSTANCE_NAME SECRET_NAME=$DS_SECRET_NAME SECRET_NAMESPACE=$DS_SECRET_NAMESPACE SECRET_KEY="" envsubst < $TP_CR_FILE | kubectl create -f - >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "The Transparent Proxy custom resource has been created."
  fi
fi

