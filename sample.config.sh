#!/bin/bash
#
# Configuration des volumes à sauvegarder
DOCKER_VOLUMES=( "volume1-data" "volume2-config" )
# Destination de la lsauvegarde
BACKUP_DIR="path/to/backups"
# Nombre de fichiers à conserver
KEEP_FILES=15
# Fichier de log
LOG_FILE="/var/log/backups.log"
# Niveau de log:
# DEBUG=1
# INFO=2
# WARNING=3
# ERROR=4
# CRITICAL=5
LOG_LEVEL=2