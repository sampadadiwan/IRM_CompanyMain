#!/bin/bash

# This script extracts server information from Capistrano deployment files
# and generates SSH aliases with numeric suffixes for each IP.

echo "# SSH Aliases for Capistrano environments"
echo ""

# Function to process a deployment file
process_file() {
    local FILE_PATH="$1"
    local ALIAS_PREFIX="$2"
    local DESCRIPTION="$3"

    if [ -f "$FILE_PATH" ]; then
        echo "# $DESCRIPTION"
        # Extract the key file, taking the first one found
        KEY=$(grep -m 1 "keys:.*pem" "$FILE_PATH" | grep -oE '~\/\.ssh\/[^\''"]+')
        # Assume user is ubuntu as per the files
        USER="ubuntu"

        local i=1
        # Find all non-commented server lines and loop through them
        grep 'server "' "$FILE_PATH" | grep -v '^\s*#' | while read -r line ; do
            IP=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')

            # Generate the numbered alias
            echo "alias ${ALIAS_PREFIX}_${i}='ssh -i $KEY $USER@$IP'"

            # Generate role-specific aliases if applicable
            if [[ "$line" == *"primary"* ]]; then
                echo "alias ${ALIAS_PREFIX}_primary='ssh -i $KEY $USER@$IP'"
            fi
            if [[ "$line" == *"LB"* ]]; then
                 echo "alias ${ALIAS_PREFIX}_lb='ssh -i $KEY $USER@$IP'"
            fi

            i=$((i+1))
        done
        echo ""
    fi
}

# Process each of the deployment files
process_file "config/deploy/staging_in.rb" "ssh_staging_in" "Staging IN"
process_file "config/deploy/production_us.rb" "ssh_production_us" "Production US"
process_file "config/deploy/production_in.rb" "ssh_production_in" "Production IN"