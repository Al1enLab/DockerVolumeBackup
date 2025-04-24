# Docker Volume Backup
Script de sauvegarde de volumes Docker.

## Configuration
Ce script se configure *via* le fichier `config.sh` présent dans le même répertoire que le script. Un exemple de configuration est fourni dans `sample.config.sh`.

### Variables
Les variables suivantes sont présentes dans le fichier de configuration :
| Variable          | Obligatoire |        Défaut   | Description                                                          |
|-------------------|-------------|-----------------|----------------------------------------------------------------------|
| `DOCKER_VOLUMES`  | **Oui**     | -               | `Bash array` contenant la liste des volumes à sauvegarder            |
| `BACKUP_DIR`      | **Oui**     | -               | Répertoire dans lequel enregistrer les sauvegardes                   |
| `KEEP_FILES`      | Non         | 10              | Nombre de versions à conserver (10 par défaut)                       |
| `LOG_FILE`        | Non         | -               | Fichier de log à utiliser (pas de log sur disque si absent)          |
| `LOG_LEVEL`       | Non         | 2               | Niveau de log (1: debug, 2: info, 3: warning, 4: error, 5: critical) |
| `CONTAINER_NAME`  | Non         | `VolumeBackup`  | Nom du conteneur lancé pour la sauvegarde                            |
| `CONTAINER_IMAGE` | Non         | `debian:latest` | Image Docker à utiliser (doit contenir la commande tar)              |

## Fonctionnement
Le script importe sa configuration, puis lance un conteneur dans lequel :
- le script monte son propre répertoire dans le conteneur
- sont montés l'ensemble des volumes listés dans le fichier de configuration (`DOCKER_VOLUMES`) dans un répertoire dédié
- est monté le répertoire de destination des sauvegardes
- est monté, si besoin, le fichier de log
- sont montés `/etc/timezone` et `/etc/localtime`

Ce conteneur exécute le script qui s'est monté lui-même pour exécuter la sauvegarde.
