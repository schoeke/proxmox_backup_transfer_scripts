#!/bin/bash

# Default configuration directory - can be overridden by environment variable
CONFIG_DIR="${CONFIG_DIR:-/etc/backup-transfer}"

# Function to clean up resources
cleanup() {
    local exit_code=$?
    log "Cleaning up temporary files..."
    [ -d "$TEMP_BACKUP_DIR" ] && rm -rf "$TEMP_BACKUP_DIR"
    exit $exit_code
}

# Function to handle interrupts
handle_interrupt() {
    log "Received interrupt signal. Terminating..."
    # Kill any running sftp processes started by this script
    pkill -P $$ sftp
    cleanup
}

# Function to show usage
usage() {
    echo "Usage: $0 -c|--config CONFIG_FILE"
    echo
    echo "CONFIG_FILE can be:"
    echo "  - An absolute path (e.g., /etc/backup-transfer/mybackup.conf)"
    echo "  - A relative path that will be searched for in $CONFIG_DIR"
    echo
    echo "Example:"
    echo "  $0 --config mybackup.conf            # Will look in $CONFIG_DIR"
    echo "  $0 --config /path/to/mybackup.conf   # Will use exact path"
    exit 1
}

# Function to load configuration from file with flexible path handling
load_config() {
    local config_file="$1"
    local full_path

    # If the path is absolute (starts with /), use it directly
    if [[ "$config_file" = /* ]]; then
        full_path="$config_file"
    else
        # Otherwise, look in CONFIG_DIR
        full_path="${CONFIG_DIR}/${config_file}"
    fi

    if [ -f "$full_path" ]; then
        echo "Loading configuration from: $full_path"
        source "$full_path"
    else
        echo "Config file not found at: $full_path"
        exit 1
    fi
}

# Function to log messages
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOGFILE:-/var/log/backup_transfer.log}"
}

# Set up signal handlers
trap handle_interrupt SIGINT SIGTERM
trap cleanup EXIT

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            CONFIG_FILE="$2"
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

# Check if config file is specified
if [ -z "$CONFIG_FILE" ]; then
    echo "Error: Config file not specified"
    usage
fi

# Load configuration
load_config "$CONFIG_FILE"

# Validate required parameters from config file
[ -z "$SOURCE_CONTAINER" ] && { echo "Container ID not specified in config"; exit 1; }
[ -z "$SOURCE_BACKUP_PATH" ] && { echo "Backup path not specified in config"; exit 1; }
[ -z "$DESTINATION_PATH" ] && { echo "Destination path not specified in config"; exit 1; }
[ -z "$DESTINATION_SERVER" ] && { echo "Destination server not specified in config"; exit 1; }

# Set default values for optional parameters
SSH_KEY="${SSH_KEY:-$HOME/.ssh/backup_transfer_key}"
LOGFILE="${LOGFILE:-/var/log/backup_transfer.log}"

# Create temporary directory for backup staging
TEMP_BACKUP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_BACKUP_DIR"' EXIT  # Ensure cleanup on script exit

# Find the most recent backup from the container
LATEST_BACKUP=$(pct exec "$SOURCE_CONTAINER" -- find "$SOURCE_BACKUP_PATH" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

if [ -z "$LATEST_BACKUP" ]; then
    log "Error: No backup files found in container $SOURCE_CONTAINER"
    exit 1
fi

# Copy backup from container to host
pct pull "$SOURCE_CONTAINER" "$LATEST_BACKUP" "$TEMP_BACKUP_DIR/$(basename "$LATEST_BACKUP")"

if [ $? -ne 0 ]; then
    log "Error: Failed to copy backup from container"
    exit 1
fi

# Transfer the backup to the destination server
TEMP_BACKUP_FILE="$TEMP_BACKUP_DIR/$(basename "$LATEST_BACKUP")"

# Modified SFTP transfer section
log "Starting file transfer..."
if ! sftp -b - "$DESTINATION_SERVER" << EOF
put "$TEMP_BACKUP_FILE" "$DESTINATION_PATH"
quit
EOF
then
    log "Error: Backup transfer failed"
    exit 1
fi

log "Backup transfer successful: $(basename "$LATEST_BACKUP")"

# Cleanup is handled by trap command above
