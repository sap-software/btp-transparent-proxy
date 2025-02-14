# SAP BTP transparent proxy scripts to facilitate lifecycle operations

The official SAP BTP transparent proxy documentation can be found [here](https://help.sap.com/docs/connectivity/sap-btp-connectivity-cf/transparent-proxy-for-kubernetes).

## Description
This repository provides shell scripts to assist with the lifecycle management of the SAP BTP transparent proxy and its operator within a Kubernetes cluster.

## Prerequisites
* A Kubernetes cluster
* kubectl installed on your machine

## Usage
### Deploy
Deploy transparent proxy with operator. The installation will result in transparent proxy operator and transparent proxy installed with predefined configurations in your Kubernetes cluster. The transparent proxy configuration is located in the Transparent Proxy custom resource and can be found in the 'sap-transp-proxy-system' namespace after installation. The default configuration is the following:
```yaml
apiVersion: operator.kyma-project.io/v1alpha1
kind: TransparentProxy
metadata:
  name: transparent-proxy
  namespace: sap-transp-proxy-system
spec:
  config:
    security:
      communication:
        internal:
          encryptionEnabled: true
    integration:
      destinationService:
        defaultInstanceName: ${SERVICE_INSTANCE_NAME}
        instances:
          - name: ${SERVICE_INSTANCE_NAME}
            serviceCredentials:
              secretKey: ${SECRET_KEY}
              secretName: ${SECRET_NAME}
              secretNamespace: ${SECRET_NAMESPACE}
      serviceMesh:
        istio:
          istio-injection: enabled
```
**Caution:** *Istio injection is enabled by default. If Istio is present in the cluster, traffic between the workloads will be encrypted, making your installation more secure. The communication with the transparent proxy will be secure, as well as the communication from the transparent proxy to the connectivity proxy, if a connectivity proxy is present. If Istio is not present, you should configure encryption manually to ensure that all communications remain secure.*

#### Deploy/Upgrade using the [SAP BTP Service Operator](https://github.com/SAP/sap-btp-service-operator)
This operation creates Service instance and Service Binding custom resources in the 'sap-transp-proxy-system' namespace, resulting in a destination service instance created in BTP. This destination service instance is loaded in the transparent proxy configuration with name "sap-transp-proxy-default".  
**Note:** *To upgrade, execute the same command in a Kubernetes cluster where you have already used this script to install the Transparent Proxy.*  
**Note:** *The upgrade operation will only upgrade to the newer version of the transparent proxy deployments without creating additional destination service instance or changing configurations.*
###### Prerequisites
* [SAP BTP Service Operator](https://github.com/SAP/sap-btp-service-operator) set up in your Kubernetes cluster

###### Command
```shell
sh deploy.sh
```
  
#### Deploy/Upgrade using destination service instance key in plain JSON format
The automation script creates a Kubernetes secret containing the service instance and loads it into the transparent proxy configuration.  
**Note:** *To upgrade, execute the same command in a Kubernetes cluster where you have already used this script to install the Transparent Proxy.*  
**Note:** *The upgrade operation will update the Transparent Proxy to the latest version. If you select the name of an existing destination service instance configuration during this process, that configuration will be updated. All other configurations will remain unchanged.*
###### Prerequisites
* Destination service instance created

###### Command
```shell
sh deploy.sh --destination-service-instance-name <value> --destination-service-key '{...}'
```
Before executing the script, ensure you have the necessary values ready to replace the placeholders in the command. The following table explains each argument you'll need to provide:

|Argument|Description|Required|
|---|---|---|
|--destination-service-instance-name (-dsin)|The local name of the destination service instance present in the transparent proxy configuration. It can be later used to reference it in Destination custom resources.|True|
|--destination-service-key (-dsk)|The service instance key obtained from the Destination service instance.|True|
  
#### Deploy/Upgrade using a Kubernetes secret holding a destination service instance key
The automation script loads the Kubernetes secret into the transparent proxy configuration.  
**Note:** *To upgrade, execute the same command in a Kubernetes cluster where you have already used this script to install the Transparent Proxy.*  
**Note:** *The upgrade operation will update the Transparent Proxy to the latest version. If you select the name of an existing destination service instance configuration during this process, that configuration will be updated. All other configurations will remain unchanged.*
###### Prerequisites
* A Kubernetes secret in your cluster that holds a destination service instance key

###### Command
```shell
sh deploy.sh --destination-service-instance-name <value> --destination-service-secret-name <secret-name> --destination-service-secret-key <secret-key> --destination-service-secret-namespace <namespace>
```
Before executing the script, ensure you have the necessary values ready to replace the placeholders in the command. The following table explains each argument you'll need to provide:

|Argument|Description|Required|
|---|---|---|
|--destination-service-instance-name (-dsin)|The local name of the destination service instance present in the transparent proxy configuration. It can be later used to reference it in Destination custom resources. *Note* If not specified, the script uses the name of the Kubernetes secret.|False|
|--destination-service-secret-name (-dssn)|The name of the existing secret, which holds the credentials for the Destination service.|True|
|--destination-service-secret-key (-dssk)|The key in the Destination service secret resource, which holds the base64-encoded value of the destination service key.|True|
|--destination-service-secret-namespace (-dssn)|The namespace of the existing secret to be used, which holds the credentials for the Destination service.|True|

### Undeploy
To undeploy the transparent proxy and its operator, execute:
```shell
sh undeploy.sh
```
**Note:** *This action will delete all Transparent Proxy resources and instances that were previously created by the script or the operator.*

## Additional Resources
[Installation with Operator](https://help.sap.com/docs/connectivity/sap-btp-connectivity-cf/installation-with-operator)  
[Configuration Guide](https://help.sap.com/docs/connectivity/sap-btp-connectivity-cf/transparent-proxy-configuration-guide)  
[Sizing Recommendations](https://help.sap.com/docs/connectivity/sap-btp-connectivity-cf/transparent-proxy-sizing-recommendations)
