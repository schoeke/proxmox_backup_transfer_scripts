# Proxmox Backup Transfer System

This project was created by me manually writing first versions of `service_psql_backups.sh` and `copy_backups.sh`. It was then iteratively extended and improved with Claude.ai's Claude 3 Haiku and Claude 3.5 Sonnet. 

The original idea was based on https://blog.vovando.dev/2017/04/11/encrypted-postgres-backups/.

This project provides a robust solution for securely transferring backups from Proxmox containers to remote storage locations. The system handles both the creation of PostgreSQL database backups within containers and their secure transfer to remote storage.

## Overview

The system solves several common challenges in backup management:

- Creating encrypted PostgreSQL database backups within containers
- Transferring backups without storing credentials in containers
- Managing multiple backup tasks through flexible configuration
- Ensuring reliable execution and monitoring of transfers
- Handling interruptions and errors gracefully

### Core Components

The system consists of three main scripts:

1. `service_psql_backup.sh`: Creates encrypted PostgreSQL database backups
2. `copy_backup.sh`: Manages individual backup transfers
3. `backup_orchestrator.sh`: Coordinates multiple backup operations

## Installation

### 1. Generate Encryption Keys

First, generate the encryption key pair **on your local machine** (not in the containers):

```bash
# Create a directory for key management
mkdir -p ~/backup-keys && cd ~/backup-keys

# Generate the private key
openssl genpkey -algorithm RSA -out backup_private.pem

# Generate the public key
openssl rsa -pubout -in backup_private.pem -out backup_public.pem

# Secure the private key
chmod 600 backup_private.pem
```

**IMPORTANT**: 
- Keep the private key (`backup_private.pem`) secure and never upload it to any container
- Store it safely as it will be needed to decrypt backups
- Consider keeping an offline copy in a secure location

### 2. Transfer Public Key to Proxmox Host

There are several ways to transfer the public key to your Proxmox host. Choose the method that best fits your security requirements:

```bash
# Option 1: Using scp
scp backup_public.pem root@proxmox:/root/

# Option 2: Using rsync
rsync -av backup_public.pem root@proxmox:/root/

# Option 3: Using a secure file transfer tool like SFTP
sftp root@proxmox
put backup_public.pem
```

Alternative methods:
- Use your configuration management system (Ansible, Salt, etc.)
- Copy via your preferred secure file sharing service
- Transfer through your internal secure file transfer infrastructure
- Use a hardware token or encrypted USB drive

Choose a method that complies with your organization's security policies and infrastructure.

### 3. Deploy Public Key to Containers

Copy the public key to each container that needs to create backups:

```bash
# For a container with ID 111
pct push 111 backup_public.pem /home/service/.ssh/service_backup_key.pem.pub

# Set proper permissions in the container
pct exec 111 -- chmod 644 /home/service/.ssh/service_backup_key.pem.pub
pct exec 111 -- chown service:service /home/service/.ssh/service_backup_key.pem.pub
```

### 4. Get the Scripts

Clone or copy the backup scripts to your Proxmox host:

```bash
git clone https://codeberg.org/andrej/proxmox_scripts.git
cd proxmox-backup-transfer
```

Copy and make the scripts executable:

```bash
cp pve_host/*.sh ~/bin/
chmod +x copy_backup.sh backup_orchestrator.sh
```

### 5. Create Configuration Directory

```bash
sudo mkdir -p /etc/backup-transfer
```

### 6. Set up SSH Transfer Keys

Generate SSH keys for secure transfers between Proxmox and backup destination:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/backup_transfer_key
# Copy the public key to your destination server
ssh-copy-id -i ~/.ssh/backup_transfer_key.pub user@destination-server
```

## Database Backup Configuration

### PostgreSQL Backup Script

The `service_psql_backup.sh` script runs inside containers to create encrypted PostgreSQL backups. Here's how to set it up:

1. Copy the backup script into the container:
```bash
# For a container with ID 111
pct push 111  ct_vm/service_psql_backup.sh /usr/local/bin/service_psql_backup.sh

# Set proper permissions in the container
pct exec 111 -- chmod u+x /home/service/bin/service_psql_backup.sh
```

2. Create required directories in the container and add script to crontab:
```bash
mkdir -p /home/service/backup/{logs,database}
chmod 700 /home/service/backup

# Add to crontab (runs daily at 1 AM)
temp_file=$(mktempd)
crontab -l > $temp_file
echo "0 1 * * * /usr/local/bin/service_psql_backup.sh production" >> $temp_file
crontab $temp_file
rm $temp_file
```

The script creates encrypted, compressed backups with these features:
- Uses bzip2 compression
- Encrypts with AES-256
- Maintains a 7-day retention period
- Validates database names to prevent injection
- Provides detailed logging

## Backup Transfer Configuration

### Directory Structure

By default, configuration files are stored in `/etc/backup-transfer`. You can override this using the `CONFIG_DIR` environment variable.

### Backup Configuration Files

Create individual `.conf` files for each backup task. Here's an example configuration (`/etc/backup-transfer/my_backup.conf`):

```bash
SOURCE_CONTAINER="111"                          # Proxmox container ID
SOURCE_BACKUP_PATH="/home/service/backup/database"  # Path to encrypted backups
DESTINATION_PATH="backups/app/"                 # Path on the destination server
DESTINATION_SERVER="nas"                        # Destination server (from SSH config)
SSH_KEY="$HOME/.ssh/backup_transfer_key"		# Optional. Defaults to this value
LOGFILE="/var/log/backup_transfer.log"			# Optional. Defaults to this value
```

### SSH Configuration

For cleaner configuration, set up SSH host aliases in `~/.ssh/config`:

```
Host nas
    HostName nas.example.com
    User backup-user
    IdentityFile ~/.ssh/backup_transfer_key
```

## Usage

### Single Backup Execution

To run a single backup task:

```bash
./copy_backup.sh --config /etc/backup-transfer/my_backup.conf
```

This will:
1. Read the specified configuration
2. Locate the most recent backup in the container
3. Transfer it to the destination server
4. Clean up temporary files

### Multiple Backup Execution

To run all configured backup tasks:

```bash
./backup_orchestrator.sh
```

Available options:

- `-d, --config-dir`: Use a custom configuration directory
- `-s, --script`: Specify a custom path to copy_backup.sh
- `-h, --help`: Display help information

Example with custom paths:

```bash
./backup_orchestrator.sh --config-dir /path/to/configs --script /path/to/copy_backup.sh
```

## Complete Backup Workflow

See also [Automation[(#Automation). The complete backup process works as follows:

1. `service_psql_backup.sh` runs inside the container at 1 AM:
   - Creates an encrypted PostgreSQL backup
   - Compresses it with bzip2
   - Stores it in /home/service/backup/database
   - Maintains a 7-day retention period

2. `backup_orchestrator.sh` runs on the Proxmox host at 2 AM:
   - Finds all backup configurations
   - For each configuration:
     - Runs `copy_backup.sh` to transfer the latest backup
     - Logs the results
   - Provides a summary of successful and failed transfers

## Decrypting Backups

When you need to decrypt a backup, use the private key you generated in step 1:

```bash
openssl smime -decrypt -in my_database.sql.bz2.enc -binary -inform DEM \
    -inkey backup_private.pem | bzcat > my_database.sql
```

## Security Features

The system implements several security best practices:

- SSH key-based authentication
- SFTP access to prevent shell access
- No credentials stored in containers
- Minimal required permissions
- Automatic cleanup of temporary files
- Secure handling of sensitive data

## Error Management

The scripts include robust error handling features:

- Thorough validation of required parameters
- Automatic cleanup of temporary files
- Proper signal handling for clean interruption
- Detailed error reporting
- Meaningful exit codes

## Automation

To automate your backups, add a cron job:

```bash
# Run all backups daily at 2 AM
0 2 * * * /path/to/backup_orchestrator.sh

# Or for individual backups
0 2 * * * /path/to/copy_backup.sh --config /etc/backup-transfer/my_backup.conf
```

## Troubleshooting Guide

### SSH Key Issues

If you encounter permission denied errors:

1. Check SSH key permissions:
   ```bash
   chmod 600 ~/.ssh/backup_transfer_key
   ```
2. Verify the key is in authorized_keys on the destination server
3. Test SSH connection manually:
   ```bash
   ssh -i ~/.ssh/backup_transfer_key user@destination-server
   ```

### SFTP Connection Problems

For SFTP connection issues:

1. Verify SSH configuration is correct
2. Check network connectivity to destination server
3. Ensure destination paths exist and are writable

### Container Access Errors

If you can't access container backups:

1. Verify Proxmox permissions
2. Check if the container is running
3. Confirm backup paths exist within the container

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Support

For issues, questions, or contributions, please [create an issue](https://codeberg.org/andrej/proxmox_scripts/issues/new) in the repository.

