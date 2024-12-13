#!/bin/bash

# Configuration
WATCH_DIRS="/etc /bin /sbin /usr/bin /usr/sbin"  # Directories to monitor
HASH_FILE="/var/log/file_hashes.db"              # Database of file hashes
LOG_FILE="/var/log/file_monitor.log"             # Log file for changes
EMAIL="your_email@domain.com"                    # Email for notifications

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Create directories if they don't exist
mkdir -p "$(dirname "$HASH_FILE")"
mkdir -p "$(dirname "$LOG_FILE")"

# Function to generate initial hash database
initialize_hashes() {
    echo "Initializing hash database..."
    > "$HASH_FILE"
    for dir in $WATCH_DIRS; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -exec sha256sum {} \; >> "$HASH_FILE"
        fi
    done
    echo "Hash database initialized at $(date)" >> "$LOG_FILE"
}

# Function to check for file changes
check_files() {
    local changes_detected=0
    local temp_file=$(mktemp)
    
    for dir in $WATCH_DIRS; do
        if [ -d "$dir" ]; then
            find "$dir" -type f -exec sha256sum {} \; >> "$temp_file"
        fi
    done
    
    # Compare current hashes with stored hashes
    while read -r line; do
        if ! grep -q "^$line$" "$HASH_FILE"; then
            changes_detected=1
            file_path=$(echo "$line" | cut -d' ' -f2-)
            echo "[$(date)] Changed file detected: $file_path" >> "$LOG_FILE"
            
            # Get file details
            permissions=$(ls -l "$file_path" | awk '{print $1}')
            owner=$(ls -l "$file_path" | awk '{print $3}')
            group=$(ls -l "$file_path" | awk '{print $4}')
            
            # Log detailed information
            {
                echo "File: $file_path"
                echo "Permissions: $permissions"
                echo "Owner: $owner"
                echo "Group: $group"
                echo "Last modified: $(stat -c %y "$file_path")"
                echo "---"
            } >> "$LOG_FILE"
        fi
    done < "$temp_file"
    
    rm "$temp_file"
    
    if [ $changes_detected -eq 1 ]; then
        send_alert
    fi
}

# Function to send alerts
send_alert() {
    local alert_message="File changes detected on $(hostname) at $(date)"
    
    # Send email alert if mail is configured
    if command -v mail &> /dev/null; then
        tail -n 20 "$LOG_FILE" | mail -s "$alert_message" "$EMAIL"
    fi
    
    # Send desktop notification if running in GUI environment
    if command -v notify-send &> /dev/null; then
        notify-send -u critical "Security Alert" "$alert_message"
    fi
    
    # Log to system journal
    logger -p auth.alert -t file_monitor "$alert_message"
}

# Main script logic
case "$1" in
    "init")
        initialize_hashes
        ;;
    "check")
        check_files
        ;;
    *)
        echo "Usage: $0 {init|check}"
        echo "  init  - Initialize hash database"
        echo "  check - Check for file changes"
        exit 1
        ;;
esac

exit 0
