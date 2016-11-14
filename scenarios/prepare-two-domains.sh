#!/bin/bash
# starts two unsecured servers in domain mode in master-slave configuration
# NO CLEANUP

ARCHIVE_PATH="$1"
TARGET_DIR="target"
MASTER_TARGET="$TARGET_DIR/domain1"
SLAVE_TARGET="$TARGET_DIR/domain2"

mkdir "$TARGET_DIR"

sh ../prepare-jboss.sh -j -z "$ARCHIVE_PATH" -u "$MASTER_TARGET"
sh ../prepare-jboss.sh -j -z "$ARCHIVE_PATH" -u "$SLAVE_TARGET"

sed -i 's/<host/<host name="slave"/g' ${SLAVE_TARGET}/domain/configuration/host-slave.xml

sh ${MASTER_TARGET}/bin/domain.sh &
sh ${SLAVE_TARGET}/bin/domain.sh --host-config=host-slave.xml -Djboss.domain.base.dir=${SLAVE_TARGET}/domain -Djboss.domain.master.address=127.0.0.1 -Djboss.bind.address=127.0.0.2 -Djboss.bind.address.management=127.0.0.2 -Djboss.bind.address.unsecure=127.0.0.2 &


