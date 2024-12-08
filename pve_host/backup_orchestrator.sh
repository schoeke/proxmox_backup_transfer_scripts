#!/bin/bash

# This script finds all configuration files in the specified directory
# and executes copy_backup.sh for each one, effectively running all configured backups

# Default configuration directory - can be overridden by environment variable
CONFIG_DIR="${CONFIG_DIR:-/etc/backup-transfer}"

# Path to the copy_backup.sh script - can be overridden by environment variable
BACKUP_SCRIPT="${BACKUP_SCRIPT:-/root/bin/copy_backups.sh}"

# Function to show usage information
usage() {
    echo "Usage: $0 [-d|--config-dir CONFIG_DIR] [-s|--script PATH_TO_SCRIPT]"
    echo
    echo "This script executes copy_backup.sh for each configuration file found"
    echo "in the specified directory."
    echo
    echo "Options:"
    echo "  -d, --config-dir    Directory containing backup configuration files"
    echo "                      Default: $CONFIG_DIR"
    echo "  -s, --script        Path to copy_backup.sh script"
    echo "                      Default: $BACKUP_SCRIPT"
    echo "  -h, --help          Show this help message"
    exit 1
}

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        -s|--script)
            BACKUP_SCRIPT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate the configuration directory
if [ ! -d "$CONFIG_DIR" ]; then
    echo "Error: Configuration directory not found: $CONFIG_DIR"
    exit 1
fi

# Validate the backup script
if [ ! -x "$BACKUP_SCRIPT" ]; then
    echo "Error: Backup script not found or not executable: $BACKUP_SCRIPT"
    exit 1
fi

# Initialize counters for summary
total_configs=0
successful_backups=0
failed_backups=0

# Create an array to store failed configurations for reporting
declare -a failed_configs

log "Starting backup execution for configurations in $CONFIG_DIR"

# Iterate over all .conf files in the configuration directory
for config_file in "$CONFIG_DIR"/*; do
    # Check if there are actually any matching files
    if [ ! -f "$config_file" ]; then
        log "No configuration files found in $CONFIG_DIR"
        exit 1
    fi

    total_configs=$((total_configs + 1))
    config_name=$(basename "$config_file")

    log "Processing configuration: $config_name"

    # Execute the backup script with the current configuration
    if "$BACKUP_SCRIPT" --config "$config_file"; then
        successful_backups=$((successful_backups + 1))
        log "Successfully completed backup for $config_name"
    else
        failed_backups=$((failed_backups + 1))
        failed_configs+=("$config_name")
        log "Failed to complete backup for $config_name"
    fi

    # Add a blank line between backups for better readability
    echo
done

# Print summary
log "Backup Execution Summary:"
log "Total configurations processed: $total_configs"
log "Successful backups: $successful_backups"
log "Failed backups: $failed_backups"

# If there were any failures, list them
if [ ${#failed_configs[@]} -gt 0 ]; then
    log "Failed configurations:"
    for failed_config in "${failed_configs[@]}"; do
        log "  - $failed_config"
    done
fi

# Exit with status based on whether all backups succeeded
[ "$failed_backups" -eq 0 ]
