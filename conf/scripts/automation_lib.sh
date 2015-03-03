#!/bin/bash
# Function library used in external automation scripts
# Generally assume runing as tomcat7 for compatbility with DMS UI calling

# Find the first live server in a tier
# Usage: firstLiveServer  tier
firstLiveServer() {
    [[ $# = 1 ]] || { echo "Internal error calling firstLiveServer" 1>&2 ; exit 1 ; }
    local tierDir="$1"

    for server in $tierDir/servers/*
    do
        if grep -qv Terminated $server/status ; then
            echo $server
            return 0
        fi
    done
    return 1
}

# Backup a server to both local disk and to S3
# The base folder should be the top level folder not including "images"/"updates" and no final "/"
# Usage: backupServer serverDir s3folder
backupServer() {
    [[ $# = 2 ]] || { echo "Internal error calling backupServer" 1>&2 ; exit 1 ; }
    local serverDir="$1"
    local s3folder="$2"

    cd /opt/dms/conf/scripts
    backupFile=$( ops/backup-server.sh $serverDir | tail -1 )

    echo "Publish to S3 images area"
    if [[ $backupFile =~ .*/images/[^-_]+-[^_]+_([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])_([0-9][0-9]-[0-9][0-9]-[0-9][0-9]).nq.gz ]]; then
        date=${BASH_REMATCH[1]}
        time=${BASH_REMATCH[2]}
        aws s3 cp $backupFile $s3folder/images/$date/$time-0000/backupServer_dump.nq.gz
    else
        echo "Badly formed backup file name, omitting S3 publish - $backupFile"
        return 1
    fi
}

# Backup the first live server in a tier to both local disk and to S3
# Usage: backupTier tierDir s3folder
backupTier() {
    [[ $# = 2 ]] || { echo "Internal error calling backupTier" 1>&2 ; exit 1 ; }
    local tierDir="$1"
    local s3folder="$2"
    local serverDir=$( firstLiveServer $tierDir )
    backupServer $serverDir $s3folder
}

# Delete all S3 folders whose name-as-date is more than AGE days old
# The base folder should not include a trailing "/"
# Usage: deleteOldS3Records s3Base age
deleteOldS3Records() {
    [[ $# = 2 ]] || { echo "Internal error calling deleteOldS3Records" 1>&2 ; exit 1 ; }
    local s3folder="$1"
    local age="$2"
    local cutoff=$(date +%F -d "-$age days")
    aws s3 ls "$s3folder/" \
    | awk '{x = $2; sub(/\//,"",x); print x;}' \
    | awk '$1 < "'$cutoff'" {print $1}' \
    | xargs -I {} aws s3 rm --recursive "$s3folder/{}"
}

# Find the most recent available dump 
# The base folder should be the top level folder not including "images"/"updates" and no final "/"
# Usage: findLastDump s3Base
findLastDump() {
    [[ $# = 1 ]] || { echo "Internal error calling findLastDump" 1>&2 ; exit 1 ; }
    local s3folder="$1"
    dump=$( aws s3 ls "$s3folder/images" --recursive | grep dump.nq.gz | tail -1 | awk '{print $4}' )
    if [[ -n $dump ]]; then
        if [[ $s3folder =~ (s3://[^/]*)/.* ]]; then
            echo "${BASH_REMATCH[1]}/$dump"
            return 0
        fi
    fi
    return 1
}

