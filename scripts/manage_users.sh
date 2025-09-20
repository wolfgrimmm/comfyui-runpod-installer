#!/bin/bash

# User management script for ComfyUI
# Add, remove, list, and switch users without Docker rebuild

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
USER_DATA_DIR="/workspace/user_data"
USERS_FILE="$USER_DATA_DIR/users.json"
CURRENT_USER_FILE="$USER_DATA_DIR/.current_user"

# Ensure user_data directory exists
mkdir -p "$USER_DATA_DIR"

# Function to initialize users.json if it doesn't exist
init_users_file() {
    if [ ! -f "$USERS_FILE" ]; then
        echo '[]' > "$USERS_FILE"
        echo -e "${YELLOW}Initialized empty users.json${NC}"
    fi
}

# Function to list all users
list_users() {
    init_users_file

    echo -e "${GREEN}=== Current Users ===${NC}"

    # Get current user
    CURRENT_USER=""
    if [ -f "$CURRENT_USER_FILE" ]; then
        CURRENT_USER=$(cat "$CURRENT_USER_FILE")
    fi

    # List users using Python (compatible with control panel format)
    python3 -c "
import json

try:
    with open('$USERS_FILE', 'r') as f:
        users = json.load(f)
except:
    print('Error reading users file')
    exit(1)

current = '$CURRENT_USER'

# Ensure it's a list (control panel format)
if not isinstance(users, list):
    users = []

if not users:
    print('No users found.')
else:
    for i, username in enumerate(users, 1):
        # All users are stored as simple strings in the control panel format
        marker = ' [CURRENT]' if str(username) == current else ''
        print(f\"{i}. {username}{marker}\")
"
}

# Function to add a new user
add_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 add <username>"
        exit 1
    fi

    # Validate username (alphanumeric and underscore only)
    if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${RED}Error: Username must be alphanumeric (letters, numbers, underscore only)${NC}"
        exit 1
    fi

    init_users_file

    # Check if user exists and add if not (control panel compatible)
    python3 -c "
import json

with open('$USERS_FILE', 'r') as f:
    users = json.load(f)

# Ensure it's a list
if not isinstance(users, list):
    users = []

# Convert username to lowercase (control panel does this)
username = '$username'.strip().lower()

# Check if user exists
if username in users:
    print('Error: User already exists!')
    exit(1)

# Add new user (simple string format for control panel)
users.append(username)

with open('$USERS_FILE', 'w') as f:
    json.dump(users, f, indent=2)

print('User added to users.json')
" || exit 1

    # Create user directories
    echo -e "${YELLOW}Creating directories for user: $username${NC}"
    mkdir -p "/workspace/input/$username"
    mkdir -p "/workspace/output/$username"
    mkdir -p "/workspace/workflows/$username"

    # Create a welcome workflow for the user
    cat > "/workspace/workflows/$username/welcome.json" << 'EOF'
{
  "last_node_id": 1,
  "last_link_id": 0,
  "nodes": [
    {
      "id": 1,
      "type": "Note",
      "pos": [100, 100],
      "size": [300, 100],
      "properties": {},
      "widgets_values": ["Welcome to ComfyUI! Your workflows will be saved here."]
    }
  ],
  "links": [],
  "version": 0.4
}
EOF

    echo -e "${GREEN}✅ User '$username' created successfully!${NC}"
    echo "Directories created:"
    echo "  - /workspace/input/$username"
    echo "  - /workspace/output/$username"
    echo "  - /workspace/workflows/$username"
}

# Function to remove a user
remove_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 remove <username>"
        exit 1
    fi

    init_users_file

    # Check if user is current user
    if [ -f "$CURRENT_USER_FILE" ]; then
        CURRENT=$(cat "$CURRENT_USER_FILE")
        if [ "$CURRENT" = "$username" ]; then
            echo -e "${RED}Error: Cannot remove current active user!${NC}"
            echo "Switch to another user first: $0 switch <other_username>"
            exit 1
        fi
    fi

    # Confirm deletion
    echo -e "${YELLOW}Warning: This will delete all data for user '$username'${NC}"
    echo "Including:"
    echo "  - /workspace/input/$username"
    echo "  - /workspace/output/$username"
    echo "  - /workspace/workflows/$username"
    read -p "Are you sure? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Cancelled."
        exit 0
    fi

    # Remove from users.json (control panel compatible)
    python3 -c "
import json

with open('$USERS_FILE', 'r') as f:
    users = json.load(f)

# Ensure it's a list
if not isinstance(users, list):
    print('Error: Invalid users file format')
    exit(1)

username = '$username'.strip().lower()

# Find and remove user
if username in users:
    users.remove(username)
else:
    print('Error: User not found!')
    exit(1)

with open('$USERS_FILE', 'w') as f:
    json.dump(users, f, indent=2)

print('User removed from users.json')
" || exit 1

    # Remove user directories
    echo -e "${YELLOW}Removing user directories...${NC}"
    rm -rf "/workspace/input/$username"
    rm -rf "/workspace/output/$username"
    rm -rf "/workspace/workflows/$username"

    echo -e "${GREEN}✅ User '$username' removed successfully!${NC}"
}

# Function to switch current user
switch_user() {
    local username="$1"

    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: $0 switch <username>"
        exit 1
    fi

    init_users_file

    # Check if user exists (control panel compatible)
    python3 -c "
import json

with open('$USERS_FILE', 'r') as f:
    users = json.load(f)

# Ensure it's a list
if not isinstance(users, list):
    print('Error: Invalid users file format')
    exit(1)

username = '$username'.strip().lower()

# Check if user exists
if username not in users:
    print('Error: User not found!')
    exit(1)
" || exit 1

    # Set as current user
    echo "$username" > "$CURRENT_USER_FILE"

    # Update symlinks for ComfyUI to use the new user's directories
    echo -e "${YELLOW}Updating symlinks for user: $username${NC}"

    # Update workflow symlink
    if [ -L "/workspace/ComfyUI/user/default/workflows" ]; then
        rm /workspace/ComfyUI/user/default/workflows
    elif [ -d "/workspace/ComfyUI/user/default/workflows" ]; then
        rm -rf /workspace/ComfyUI/user/default/workflows
    fi
    mkdir -p /workspace/ComfyUI/user/default
    ln -sf "/workspace/workflows/$username" /workspace/ComfyUI/user/default/workflows

    # Note: Output and input don't need user-specific symlinks as ComfyUI
    # saves to the base directories, and the app.py handles user separation

    echo -e "${GREEN}✅ Switched to user '$username'${NC}"
    echo -e "${YELLOW}Note: Restart ComfyUI for changes to take effect${NC}"
    echo "To restart ComfyUI:"
    echo "  pkill -f 'python main.py'"
    echo "  Or use the Control Panel to restart"
}

# Function to show current user
current_user() {
    if [ -f "$CURRENT_USER_FILE" ]; then
        CURRENT=$(cat "$CURRENT_USER_FILE")
        echo -e "${GREEN}Current user: $CURRENT${NC}"

        # Show user stats
        if [ -d "/workspace/output/$CURRENT" ]; then
            OUTPUT_COUNT=$(find "/workspace/output/$CURRENT" -type f \( -name "*.png" -o -name "*.jpg" \) 2>/dev/null | wc -l)
            echo "  Output files: $OUTPUT_COUNT"
        fi

        if [ -d "/workspace/workflows/$CURRENT" ]; then
            WORKFLOW_COUNT=$(find "/workspace/workflows/$CURRENT" -name "*.json" 2>/dev/null | wc -l)
            echo "  Workflows: $WORKFLOW_COUNT"
        fi
    else
        echo -e "${YELLOW}No current user set${NC}"
        echo "Use: $0 switch <username>"
    fi
}

# Function to show help
show_help() {
    echo "ComfyUI User Management Script"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list              List all users"
    echo "  add <username>    Add a new user"
    echo "  remove <username> Remove a user and their data"
    echo "  switch <username> Switch to a different user"
    echo "  current          Show current active user"
    echo "  help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add john"
    echo "  $0 switch john"
    echo "  $0 list"
    echo "  $0 remove john"
}

# Main command handler
case "${1:-}" in
    list)
        list_users
        ;;
    add)
        add_user "$2"
        ;;
    remove)
        remove_user "$2"
        ;;
    switch)
        switch_user "$2"
        ;;
    current)
        current_user
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        if [ -z "${1:-}" ]; then
            show_help
        else
            echo -e "${RED}Error: Unknown command '$1'${NC}"
            echo ""
            show_help
            exit 1
        fi
        ;;
esac