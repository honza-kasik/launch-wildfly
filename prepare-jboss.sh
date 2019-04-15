#!/bin/bash
DO_NOT_START=false
SECURED=false
START_IN_DOMAIN=false

while getopts ":z:u:sc:dj" opt; do
    case $opt in
        z)
            INSTALLATION_ZIP_PATH=$OPTARG
            ;;
        u)
    	    INSTALL_PATH=$OPTARG
            EAP_HOME="$INSTALL_PATH"
            ;;
        s)
            SECURED=true
            ;;
        c) #HAL module will be replaced
            NEW_HAL_JAR_PATH=$OPTARG
            PATH_TO_CONSOLE="$EAP_HOME/modules/system/layers/base/org/jboss/as/console/main"
            ;;
        d)
            START_IN_DOMAIN=true
            ;;
        j)
            DO_NOT_START=true
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

function inPlaceSed {
    sed -i.bak "$1" "$2" || exit 1
}

function verifyEnvironmentVariables() {
    if [ -z "$INSTALLATION_ZIP_PATH" ]; then
        throwerr "Name of EAP zip is not defined!"
    fi

    if [ -z "$INSTALL_PATH" ]; then
        throwerr "Name of unzipped EAP folder is not defined!"
    fi
}

function removePreviouslyUnzippedInstallation() {
    rm -r $INSTALL_PATH
    printlog "Previously unzipped EAP removed!"
}

function unzipEAP() {
   main_folder=$(unzip -l "$INSTALLATION_ZIP_PATH" | head -n 4 | tail -n 1 | awk '{print $4}')
   printlog "Main in archive folder in archive is '$main_folder'"
   unzip -q "$INSTALLATION_ZIP_PATH" -d "$INSTALL_PATH"
   printlog "EAP unzipped in '$INSTALL_PATH/$main_folder'!"
   printlog "Moving files from '$INSTALL_PATH/$main_folder*' to '$INSTALL_PATH'"
   mv "$INSTALL_PATH"/$main_folder* "$INSTALL_PATH"
}

function waitForServerStarted() {
    local CHECK_TIMEOUT=$1;
    local SERVER_STATE

    if [[ $1 =~ ^[0-9]+$ ]]; then
        printlog "${FUNCNAME[0]}: Checking if server is running with timeout of $1 s.";
    else
        printlog "${FUNCNAME[0]}: Checking if server is running with default timeout of 60 s.";
        CHECK_TIMEOUT=60;
    fi

    while [[ $CHECK_TIMEOUT -ne 0 ]]
    do
        sleep 1;
        SERVER_STATE=$(runCliCommand ':read-attribute(name=server-state)' | grep result);
        if [[ -z $SERVER_STATE ]]; then
            SERVER_STATE="stopped";
        else
            SERVER_STATE=$(echo "$SERVER_STATE" | tr -s \" " " | cut -d ' ' -f 4);
        fi
        printlog "${FUNCNAME[0]}: Server is $SERVER_STATE";
        if [[ $SERVER_STATE == "running" ]]; then
            return 0;
        fi
        ((CHECK_TIMEOUT-=1));
    done
    printerr "${FUNCNAME[0]}: Server didn't start within ${CHECK_TIMEOUT} seconds."
    return 1;
}

function runCliCommand() {
    local command="${1}"
    sh ${INSTALL_PATH}/bin/jboss-cli.sh --connect "${command}" || return 1
}

function unsecureStandaloneMode() {
    startServer true &
    waitForServerStarted || return 1
    printlog "Unsecuring server in standalone mode..."
    runCliCommand "/core-service=management/management-interface=http-interface:undefine-attribute(name=security-realm)" || return 1
    stopServer
}

function unsecureDomainMode() {
    startServer true &
    waitForServerStarted || return 1
    printlog "Unsecuring server in domain mode..."
    runCliCommand "/host=master/core-service=management/management-interface=http-interface:undefine-attribute(name=security-realm)" || return 1
    stopServer
}

function unsecureServer() {
    if test $START_IN_DOMAIN = true; then
        unsecureDomainMode || return 1
    else
        unsecureStandaloneMode || return 1
    fi   
}
#./bin/jboss-cli.sh -c --commands="/core-service=management/management-interface=http-interface:undefine-attribute(name=security-realm),:reload"

function replaceOldHALModule() {
   printlog "Replacing HAL module in slot '$PATH_TO_CONSOLE'!"
   old_console_jar_name=$(ls $PATH_TO_CONSOLE/*.jar | xargs -n 1 basename)
   new_console_jar_name=$(basename "$NEW_HAL_JAR_PATH")
   printlog "Replacing old console '$old_console_jar_name' by '$new_console_jar_name'!"

   rm $PATH_TO_CONSOLE/*.jar || return 1
   cp "$NEW_HAL_JAR_PATH" "$PATH_TO_CONSOLE/$new_console_jar_name" || return 1

   #replace name in module.xml so the new console loads
   inPlaceSed "s/resource-root path=\"$old_console_jar_name\"/resource-root path=\"$new_console_jar_name\"/g" "$PATH_TO_CONSOLE/module.xml" || return 1
}

function startServer() {
    local silent_output="${1:-false}"

    if [ "$START_IN_DOMAIN" = true ]; then
        printlog "Starting EAP in domain mode!"
        if test ${silent_output} = true; then
            sh "$EAP_HOME/bin/domain.sh" > /dev/null
        else    
            sh "$EAP_HOME/bin/domain.sh"
        fi    
    else
        printlog "Starting EAP in standalone mode!"
        if test ${silent_output} = true; then
            sh "$EAP_HOME/bin/standalone.sh" -c standalone-full-ha.xml > /dev/null
        else    
            sh "$EAP_HOME/bin/standalone.sh" -c standalone-full-ha.xml
        fi    
    fi
}

function stopServer()  {
    if [ "$START_IN_DOMAIN" = true ]; then
        printlog "Stopping EAP in domain mode!"
        runCliCommand "shutdown --host=master"
    else
        printlog "Stopping EAP in standalone mode!"
        runCliCommand "shutdown"
    fi
}

verifyEnvironmentVariables
removePreviouslyUnzippedInstallation
unzipEAP

#unsecure
if [ "$SECURED" = false ]; then
    unsecureServer || throwerr "Failed to unsecure server! Exiting!"
else 
    printlog "Leaving server secured!"
fi

#replace old console
if [ -n "$NEW_HAL_JAR_PATH" ]; then
    replaceOldHALModule || throwerr "Failed to replace HAL module! Exiting!"
fi

#run EAP
if [ "$DO_NOT_START" = false ]; then
    startServer
fi

