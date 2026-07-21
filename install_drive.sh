#!/bin/bash

# Script to install Frappe Drive app
# This script can be used either in a Docker container or local bench setup

echo "Installing Frappe Drive App..."

# Check if we're in a Docker container
if [ -f /.dockerenv ]; then
    echo "Detected Docker environment"
    cd /home/frappe/frappe-bench
else
    echo "Local environment detected"
    # Try to find bench directory
    if [ ! -f "./bench" ] && [ ! -d "./apps" ]; then
        echo "Error: Not in a Frappe bench directory"
        echo "Please navigate to your bench directory first"
        exit 1
    fi
fi

# Install Drive app
echo "Getting Drive app from GitHub..."
bench get-app https://github.com/frappe/drive --branch main

if [ $? -eq 0 ]; then
    echo "Drive app downloaded successfully"
    
    # Check available sites
    echo "Available sites:"
    bench list-sites
    
    # Install on specified site (modify as needed)
    SITE_NAME="hrms.localhost"
    echo "Installing Drive app on site: $SITE_NAME"
    
    bench --site $SITE_NAME install-app drive
    
    if [ $? -eq 0 ]; then
        echo "Drive app installed successfully on $SITE_NAME"
        echo "Restarting services..."
        bench --site $SITE_NAME migrate
        bench restart
    else
        echo "Failed to install Drive app on $SITE_NAME"
        echo "Make sure the site exists and is accessible"
    fi
else
    echo "Failed to download Drive app"
    echo "Check your internet connection and GitHub access"
fi

echo "Installation script completed."