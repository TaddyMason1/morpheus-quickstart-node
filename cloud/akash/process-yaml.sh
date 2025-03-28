#!/bin/bash

set -e

SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/config.sh"

# Process the deployment template with environment variables, paste this processed yaml file into akash console.
echo "Processing deployment template..."
envsubst < "${SCRIPT_DIR}/deploy.yml" > "${SCRIPT_DIR}/deploy.processed.yml"