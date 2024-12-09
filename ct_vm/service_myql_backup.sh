#!/bin/bash
# #######################
# Postgresql database backup script.
# - this runs out of a user's crontab
# - this runs once per day
# - this takes a database name as the first argument, defaults to 'production'
# - this compresses the dump with bzip2 compression
# - this encrypts the dump with aes 256
#
# To extract:
# You need the private key associated with the
# public key defined by the backup_public_key variable.
#
#   openssl smime -decrypt -in my_database.sql.sql.bz2.enc -binary -inform DEM -inkey private.pem | bzcat >  my_database.sql.sql
#
# #######################

set -x # DEBUG
umask 0070
log_file="/home/service/backup/logs/backup_$(date +%Y%m%d).log"


# Database Name
database_name="${1:-production}"

# Validate database name to prevent injection
if [[ ! "$database_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
    echo "$(date) Invalid database name: ${database_name}" >> "${log_file}"
    exit 1
fi

backup_public_key="/home/service/.ssh/service_backup_key.pem.pub"
backup_dir="/home/service/backup/database"
backup_date=$(date +%Y%m%d%H%M)
backup_file="${backup_dir}/${database_name}_${backup_date}.bz2.enc"

echo "$(date) Removing old backups." >> "${log_file}"
find "${backup_dir}" -type f -name "${database_name}_*.bz2.enc" -mtime +7 -exec rm -f {} +

echo "$(date) Dumping ${database_name} to ${backup_file}" >> "${log_file}"

mysqldump "${database_name}" | bzip2 -c \
| openssl smime -encrypt -aes256 -binary -outform DEM \
-out "${backup_file}" "${backup_public_key}"

echo "$(date) Backup completed for ${database_name}." >> "${log_file}"
