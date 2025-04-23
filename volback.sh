#!/bin/bash
#
# Script de sauvegarde de conteneurs Docker
#
# Lance un conteneur dans lequel sont montés les volumes à sauvegarder
# Lance un script qui sauvegarde l'ensemble des volumes montés dans
# le répertoire de sauvegarde désigné
#
# La configuration des volumes à sauvegarder et le répertoire de destination
# se fait dans config.sh
#

# Les variables en readonly ne peuvent pas être surchargées dans le fichier de configuration.
# Les autres peuvent être surchargées.

# Confiuguration des sauvegardes
KEEP_FILES=10
DATE_SUFFIX_FORMAT='_%Y%m%d_%H%M%S'
LOG_LEVEL=2

# Configuration du conteneur
CONTAINER_NAME="VolumeBackup"
CONTAINER_IMAGE="debian:latest"
readonly CONTAINER_SCRIPT_PATH="/scripts"
readonly CONTAINER_SOURCE_PATH='/source'
readonly CONTAINER_DESTINATION_PATH='/backups'
readonly CONTAINER_TMP_DIR='/tmp'
readonly CONTAINER_LOG_FILE='/tmp/app.log'

# Chemins script et config
readonly HOST_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOST_SCRIPT_FILE="${HOST_SCRIPT_PATH}/$( basename $0 )"
readonly HOST_SCRIPT_CONFIG="${HOST_SCRIPT_PATH}/config.sh"

# Mappings dans le conteneur
readonly CONTAINER_SCRIPT_FILE="${CONTAINER_SCRIPT_PATH}/$( basename $0 )"
readonly CONTAINER_CONFIG_FILE="${CONTAINER_SCRIPT_PATH}/config.sh"

# Exit status
readonly ERR_BACKUP_DIR_CREATE=1
readonly ERR_BACKUP_DIR_WRITE=2
readonly ERR_BACKUP_FAILED=3
readonly ERR_SOURCE_VOLUME_ABSENT=5
readonly ERR_SOURCE_VOLUME=6
readonly ERR_DESTINATION_VOLUME_ABSENT=7
readonly ERR_DESTINATION_VOLUME=8
readonly ERR_MISSING_CONFIG_FILE=10
readonly ERR_MISSING_DOCKER_VOLUMES=11
readonly ERR_MISSING_BACKUP_DIR=12
readonly ERR_UNKNOWN_BACKUP_STEP=13

# Niveaux de log
readonly LOG_LEVEL_DEBUG=1
readonly LOG_LEVEL_INFO=2
readonly LOG_LEVEL_WARNING=3
readonly LOG_LEVEL_ERROR=4
readonly LOG_LEVEL_CRITICAL=5

####################
# Fonctions de log #
####################

logecho() {
    local msg="$@"
    local msg_stamp="[ $( date --rfc-3339=seconds ) ]"
    echo "${msg_stamp} $@"
    if [ ! -z "${LOG_FILE}" ]; then
        echo "${msg_stamp} $@" >> ${LOG_OUTPUT}
    fi
}
debug() {
    if [[ $LOG_LEVEL_DEBUG -ge $LOG_LEVEL ]]; then
        logecho "[DEBUG   ] $@"
    fi
}
info() {
    if [[ $LOG_LEVEL_INFO -ge $LOG_LEVEL ]]; then
        logecho "[INFO    ] $@"
    fi
}
warning() {
    if [[ $LOG_LEVEL_WARNING -ge $LOG_LEVEL ]]; then
        logecho "[WARNING ] $@"
    fi
}
error() {
    if [[ $LOG_LEVEL_ERROR -ge $LOG_LEVEL ]]; then
        logecho "[ERROR   ] $@"
    fi
}
critical() {
    if [[ $LOG_LEVEL_CRITICAL -ge $LOG_LEVEL ]]; then
        logecho "[CRITICAL] $@"
    fi
}

######################################
# Fonctions de gestions des fichiers #
######################################

create_backup_dir() {
    # $1: nom du répertoire à créer
    local backup_dir=$1
    if [ ! -d "${backup_dir}" ]; then
        info "Creating backup dir ${backup_dir}"
        mkdir -p "${backup_dir}"
        if [ $? != "0" ]; then
            warning "Failed to create ${backup_dir}, aborting current backup."
            return $ERR_BACKUP_DIR_CREATE
        fi
    fi
    if [ ! -w "${backup_dir}" ]; then
        warning "${backup_dir} cannot be written, aborting current backup."
        return $ERR_BACKUP_DIR_WRITE
    fi
    return 0
}

backup_volume() {
    # $1: chemin du volume à sauvegarder
    # $2: répertoire de la sauvegarde
    local volume="$1"
    local backup_dir="$2"
    local backup_filename="$( basename ${volume} )$( date +"${DATE_SUFFIX_FORMAT}" ).tar.gz"
    local backup_file="${backup_dir}/${backup_filename}"
    info "Backuping ${volume} to file ${backup_file}"
    tar -zcf "${backup_file}" -C "${volume}" . 2>/tmp/err.log
    result=$?
    if [ ${result} != "0" ]; then
        warning "Encountered errors during backup (volume ${volume}, backup ${backup_file}): exit status ${result}"
        while read -r line; do
            debug "Error: ${line}"
        done < /tmp/err.log        
        return $ERR_BACKUP_FAILED
    fi
    return 0
}

prune_dir() {
    # $1: Répertoire à nettoyer
    local backup_dir="$1"
    for file in $( ls -tp "${backup_dir}" | grep -v '/$' | tail -n +$(( ${KEEP_FILES} + 1 )) ); do
        info "Pruning file ${file}"
        rm "${backup_dir}/${file}"
    done
}

#########################
# Fonctions principales #
#########################

run_container() {
    # On vérifie que les variables des volumes sont définies
    if [ -z "${DOCKER_VOLUMES}" ]; then
        critical "Missing DOCKER_VOLUMES variable - check config.sh"
        exit ${ERR_MISSING_DOCKER_VOLUMES}
    fi

    if [ -z "${BACKUP_DIR}" ]; then
        critical "Missing BACKUP_DIR variable - check config.sh"
        exit ${ERR_MISSING_BACKUP_DIR}
    fi

    local next_step="backup"

    # Construction de la commande de lancement du conteneur
    docker_command='docker run --rm'
    docker_command="${docker_command} --name ${CONTAINER_NAME}"
    docker_command="${docker_command} --cpus 1"

    # Ajout du répertoire de ce script
    docker_command="${docker_command} --volume ${HOST_SCRIPT_PATH}:${CONTAINER_SCRIPT_PATH}:ro"

    # Ajout du volume vers lequel sauvegarder les autres volumes
    docker_command="${docker_command} --volume ${BACKUP_DIR}:${CONTAINER_DESTINATION_PATH}"

    # Ajout des volumes à sauvegarder
    for volume in ${DOCKER_VOLUMES[@]}; do
        docker_command="${docker_command} --volume ${volume}:${CONTAINER_SOURCE_PATH}/${volume}:ro"
    done

    # De quoi avoir le bon horodatage dans le conteneur
    docker_command="${docker_command} --volume /etc/timezone:/etc/timezone:ro"
    docker_command="${docker_command} --volume /etc/localtime:/etc/localtime:ro"

    # Définition de l'étape
    docker_command="${docker_command} --env BACKUP_STEP=${next_step}"

    # # Et du log si besoin
    if [ ! -z "${LOG_FILE}" ]; then
        [ ! -f "${LOG_FILE}" ] && touch "${LOG_FILE}"
        docker_command="${docker_command} --volume ${LOG_FILE}:${CONTAINER_LOG_FILE}"
    fi
    docker_command="${docker_command} ${CONTAINER_IMAGE} bash -c ${CONTAINER_SCRIPT_FILE}"

    # Lancement du conteneur à proprement parler
    debug "Docker command : ${docker_command}"
    info "Running container"
    eval "${docker_command}"
    result=$?
    debug "Container exit status: ${result}"
    return ${result}
}

run_backup() {
    # Sauvegarde à proprement parler
    info "Starting backup from ${CONTAINER_SOURCE_PATH} to ${CONTAINER_DESTINATION_PATH}"
    for volume in $( ls -d ${CONTAINER_SOURCE_PATH}/*/ ); do
        volume_name="$( basename ${volume} )"
        backup_dir="${CONTAINER_DESTINATION_PATH}/${volume_name}"
        backup_filename="$( basename ${volume} )$( date +"${DATE_SUFFIX_FORMAT}" ).tar.gz"
        backup_file="${backup_dir}/${backup_filename}"
        tmp_file="${CONTAINER_TMP_DIR}/${backup_filename}"
        md5_file="${backup_dir}/.last.md5"
        last_stamp_file="${backup_dir}/.last_timestamp.txt"
        # Création du fichier de sauvegarde
        info "Backuping ${volume}"
        tar -zcf "${tmp_file}" -C "${volume}" . 2>/tmp/err.log
        result=$?
        if [ ${result} != "0" ]; then
            warning "Encountered errors during backup (volume ${volume}, backup ${tmp_file}): exit status ${result}"
            while read -r line; do
                debug "Error: ${line}"
            done < /tmp/err.log
        fi
        last_md5=$( md5sum ${tmp_file} | awk '{ print $1 }' )
        debug "New backup MD5 sum : ${last_md5}"
        # On vérifie si on a une somme MD5 pour la dernière sauvegarde
        if [ -f "${md5_file}" ]; then
            previous_md5="$( cat ${md5_file} )"
            debug "Previous   MD5 sum : ${previous_md5}"
        else
            previous_md5=""
            debug "No previous MD5 sum"
        fi
        # Si les MD5 diffèrent, on copie la nouvelle sauvegarde vers sa destionation...
        if [ "${previous_md5}" != "${last_md5}" ]; then
            info "Previous and new backups MD5 checksums differ, copying backup file to ${backup_file}"
            create_backup_dir "${backup_dir}"
            mv "${tmp_file}" "${backup_file}"
            echo "${last_md5}" > ${md5_file}
        else
            info "Previous and new backups MD5 checksums are identical, skipping"
            rm "${tmp_file}"            
        fi
        date +'%Y%m%d_%H%M%S' > ${last_stamp_file} 

        prune_dir "${backup_dir}"
    done
}

#######################
# Programme principal #
#######################

if [ ! -f "${HOST_SCRIPT_CONFIG}" ]; then
    critical "Config file (${HOST_SCRIPT_CONFIG}) not found, aborting."
    exit ${ERR_MISSING_CONFIG_FILE}
fi

. ${HOST_SCRIPT_CONFIG}
[ -z "${BACKUP_STEP}" ] && BACKUP_STEP="container"

info "Starting volume backup"

if [ "${BACKUP_STEP}" == "container" ]; then
    LOG_OUTPUT=${LOG_FILE}
    run_container
    exit $?
elif [ "${BACKUP_STEP}" == "backup" ]; then
    LOG_OUTPUT=${CONTAINER_LOG_FILE}
    run_backup
    exit $?
else
    critical "Unknown backup step ${BACKUP_STEP}, aborting."
    exit ${ERR_UNKNOWN_BACKUP_STEP}
fi
info "Exiting"
