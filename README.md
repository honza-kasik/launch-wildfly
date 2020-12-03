Simple launch script simplyfing repeated start of Wildfly/RedHat EAP.

## Arguments
`./prepare-jboss.sh -z <PATH> -u <PATH> [-s] [-c <PATH>] [-d] [-j]`

 * `-z <PATH>` – path to Wildfly installation zip file
 * `-u <PATH>` – installation path
 * `[-s]` – if specified, server will be kept secured
 * `[-c <PATH>]` – path to HAL console module which will be used to replace default one
 * `[-d]` – if specified, server will be started in domain mode
 * `[-j]`– perform all steps but starting the server
