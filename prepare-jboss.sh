#!/bin/bash
SECURED=false
START_IN_DOMAIN=false

while getopts ":z:u:sc:d" opt; do
    case $opt in
        z)
            INSTALLATION_ZIP_PATH=$OPTARG
            ;;
        u)
	    INSTALL_PATH=$OPTARG
            EAP_HOME="$INSTALL_PATH/jboss-eap-7.0"
            ;;
        s)
            SECURED=true
            ;;
        c) #HAL module will be replaced
            NEW_HAL_JAR_PATH=$OPTARG
            PATH_TO_CONSOLE="$EAP_HOME/modules/system/layers/base/org/jboss/as/console/eap"
            ;;
        d)
            START_IN_DOMAIN=true
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

function printlog {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

function printerr {
    >&2 printlog "$1"
}

function throwerr {
    printerr "$1"
    ERROR_CODE=1
    if [ -n "$2" ]; then
        ERROR_CODE=$2
    fi
    exit $ERROR_CODE
}

function verifyEnvironmentVariables() {
    if [ -z "$INSTALLATION_ZIP_PATH"]; then
        throwerr "Name of EAP zip is not defined!"
    fi

    if [ -z "$INSTALL_PATH"]; then
        throwerr "Name of unzipped EAP folder is not defined!"
    fi
}

function removePreviouslyUnzippedInstallation() {
   rm -r $INSTALL_PATH
   printlog "Previously unzipped EAP removed!"
}

function unzipEAP() {
   unzip "$INSTALLATION_ZIP_PATH" -d "$INSTALL_PATH"
   printlog "EAP unzipped"
}

function unsecureConfigurationFile() {
    sed "s/http-interface security-realm=\"ManagementRealm\"/http-interface/g" -i "$1"
    printlog "Unsecured EAP in $1"
}

function unsecureServer() {
    unsecureConfigurationFile "$EAP_HOME/domain/configuration/host.xml"
    unsecureConfigurationFile "$EAP_HOME/standalone/configuration/standalone-ha.xml"
    unsecureConfigurationFile "$EAP_HOME/standalone/configuration/standalone-full-ha.xml"
}
#./bin/jboss-cli.sh -c --commands="/core-service=management/management-interface=http-interface:undefine-attribute(name=security-realm),:reload"

function replaceOldHALModule() {
   old_console_jar_name=$(ls "$PATH_TO_CONSOLE/*.jar" | xargs -n 1 basename)
   new_console_jar_name=$(basename "$NEW_HAL_JAR_PATH")
   printlog "Replacing old console \'$old_console_jar_name\' by \'$new_console_jar_name\'!"

   rm "$PATH_TO_CONSOLE/*.jar"
   cp "$NEW_HAL_JAR_PATH" "$PATH_TO_CONSOLE/$new_console_jar_name"

   #replace name in module.xml so the new console loads
   sed "s/resource-root path=\"$old_console_jar_name\"/resource-root path=\"$new_console_jar_name\"/g" -i "$PATH_TO_CONSOLE/module.xml"
}

verifyEnvironmentVariables
removePreviouslyUnzippedInstallation
unzipEAP

#unsecure
if [ "$SECURED" = false ]; then
    unsecureServer
else 
    printlog "Leaving server secured!"
fi

#replace old console
if [ -n "$NEW_HAL_JAR_PATH" ]; then
    replaceOldHALModule
fi

#run EAP
if [ "$START_IN_DOMAIN" = true ]; then
    printlog "Starting EAP in domain mode!"
    sh "$EAP_HOME/bin/domain.sh"
else
    printlog "Starting EAP in standalone mode!"
    sh "$EAP_HOME/bin/standalone.sh" -c standalone-full-ha.xml
fi

