#!/bin/bash

export AKASH_KEY_NAME="" #Leave this blank if you do not have any keys


#AKASH NETWORK CONFIGURATION
export AKASH_NET="https://raw.githubusercontent.com/akash-network/net/main/mainnet"
export AKASH_VERSION="$(curl -s https://api.github.com/repos/akash-network/provider/releases/latest | jq -r '.tag_name')"
export AKASH_CHAIN_ID="$(curl -s "$AKASH_NET/chain-id.txt")"
export AKASH_NODE="$(curl -s "$AKASH_NET/rpc-nodes.txt" | shuf -n 1)"

#AKASH BID CONFIGURATION
export AKASH_GAS=auto
export AKASH_GAS_ADJUSTMENT=1.25
export AKASH_GAS_PRICES=0.0025uakt
export AKASH_SIGN_MODE=amino-json


#CHECKS IF AKASH CONFIGURATION IS SET UP PROPERLY
deploy_to_akash() {
  # Validates Akash cli installation
  check_akash_version
  # Akash keys menu
  check_keys  
  # Check akash network configuration.
  check_backend_akash
  # Make sure address is funded with at least 5 AKT.
  check_balance
  # Checks the key's certificate. If one does not exist, will make new one.
  check_certificate
  # Process deployment file.
  ./process-yaml.sh
  # Submit deployment to akash network
  create_and_save_deployment
  # Retrieve bids and saves to local file.
  get_and_save_bids
  # using local bids file, creates cli menu for the user to select a provider
  select_provider_from_bids
  # Create and submit lease agreement with provider to host consumer node.
  create_lease
  # Send file manifest to deployment.
  send_manifest
  #retrieve consumer and provider urls.
  get_service_url
}

# Ensures user has homebrew and akash cli installed
check_akash_version() {
  # ───────────────────────────────────────────────
  # 🔍 Check if Akash CLI is installed
  # ───────────────────────────────────────────────

  if ! command -v akash >/dev/null 2>&1; then
    echo "❌ Akash CLI is not installed or not in your PATH."
    read -rp "❓ Would you like to install it now? (y/n): " INSTALL_AKASH

    if [[ "$INSTALL_AKASH" =~ ^[Yy]$ ]]; then
      # Check for Homebrew
      if ! command -v brew >/dev/null 2>&1; then
        echo "🍺 Homebrew is not installed."
        read -rp "❓ Would you like to install Homebrew first? (y/n): " INSTALL_BREW

        if [[ "$INSTALL_BREW" =~ ^[Yy]$ ]]; then
          echo "📦 Installing Homebrew..."
          /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

          # Load Homebrew into PATH if necessary
          if [[ -d "/opt/homebrew/bin" ]]; then
            export PATH="/opt/homebrew/bin:$PATH"
          elif [[ -d "/usr/local/bin" ]]; then
            export PATH="/usr/local/bin:$PATH"
          fi

          if ! command -v brew >/dev/null 2>&1; then
            echo "❌ Homebrew installation failed. Please install it manually from https://brew.sh"
            exit 1
          fi
        else
          echo "🚫 Cannot proceed without Homebrew. Exiting."
          exit 1
        fi
      fi

      echo "📦 Installing Akash CLI using Homebrew..."
      brew tap akash-network/tap
      brew install akash

      if ! command -v akash >/dev/null 2>&1; then
        echo "❌ Akash CLI installation failed. Please try installing manually."
        exit 1
      fi

      echo "✅ Akash CLI installed successfully."
    else
      echo "🚫 Akash CLI installation canceled. Exiting."
      exit 1
    fi
  fi

  # ✅ Confirm CLI is installed
  AKASH_VERSION_INSTALLED=$(akash version 2>/dev/null || echo "unknown")
  echo "✅ Akash CLI detected — version: $AKASH_VERSION_INSTALLED"
  sleep 2
}


check_keys() {
  echo "🔍 Checking for existing Akash keys..."
  KEY_LIST=$(provider-services keys list --keyring-backend os 2>/dev/null)

  # Extract key names into array
  KEY_NAMES=($(echo "$KEY_LIST" | awk '/^- name:/ {print $3}'))

  # If keys exist, let the user pick one
  if [ ${#KEY_NAMES[@]} -gt 0 ]; then
    echo -e "\n🔐 Found existing Akash wallets:"
    SELECTED_KEY=$(printf "%s\n" "${KEY_NAMES[@]}" | gum choose --header="🎯 Select a wallet" --cursor="👉")

    if [ -z "$SELECTED_KEY" ]; then
      echo "❌ No wallet selected. Exiting."
      exit 1
    fi

    export AKASH_KEY_NAME="$SELECTED_KEY"
    echo "✅ Using wallet: $AKASH_KEY_NAME"

  else
    echo -e "\n⚠️ No wallets found in your Akash keyring."

    WALLET_ACTION=$(gum choose --cursor="👉" "Create New Wallet" "Import Existing Wallet")

    case "$WALLET_ACTION" in
      "Create New Wallet")
        read -rp "🆕 Enter a name for your new wallet key: " AKASH_KEY_NAME
        AKASH_ACCOUNT_ADDRESS=provider-services keys add "$AKASH_KEY_NAME" --keyring-backend os
        read -rp "👉 \n\nSAVE YOUR MNEMONIC PHRASE SOMEWHERE SAFE.\nThen, fund your Akash wallet with at least 5 AKT.\nPress Enter to continue..."
        echo -e "✅ Created wallet: $AKASH_KEY_NAME"
        ;;
      "Import Existing Wallet")
        read -rp "📥 Enter a name for your wallet: " AKASH_KEY_NAME
        read -rp "🔑 Paste your 24-word mnemonic: " MNEMONIC
        echo "$MNEMONIC" | provider-services keys add "$AKASH_KEY_NAME" --recover --keyring-backend os
        echo -e "✅ Imported wallet: $AKASH_KEY_NAME"
        ;;
      *)
        echo "❌ Invalid option. Exiting."
        exit 1
        ;;
    esac

    export AKASH_KEY_NAME="$AKASH_KEY_NAME"
  fi
}


check_backend_akash() {
  # 💾 AKASH_KEYRING_BACKEND
  if [ -z "$AKASH_KEYRING_BACKEND" ]; then
    AKASH_KEYRING_BACKEND="os"
    echo "💾 AKASH_KEYRING_BACKEND not set — using default: $AKASH_KEYRING_BACKEND"
  else
    echo "💾 AKASH_KEYRING_BACKEND already set: $AKASH_KEYRING_BACKEND"
  fi
  sleep 1.5

  # 🌐 AKASH_NET
  if [ -z "$AKASH_NET" ]; then
    AKASH_NET="https://raw.githubusercontent.com/akash-network/net/main/mainnet"
    echo "🌐 AKASH_NET not set — using default mainnet URL: $AKASH_NET"
  else
    echo "🌐 AKASH_NET already set: $AKASH_NET"
  fi
  sleep 1.5

  # 🔗 AKASH_CHAIN_ID
  if [ -z "$AKASH_CHAIN_ID" ]; then
    AKASH_CHAIN_ID=$(curl -s "$AKASH_NET/chain-id.txt")
    echo "🔗 AKASH_CHAIN_ID not set — fetched from net: $AKASH_CHAIN_ID"
  else
    echo "🔗 AKASH_CHAIN_ID already set: $AKASH_CHAIN_ID"
  fi
  sleep 1.5

  # 📡 AKASH_NODE
  if [ -z "$AKASH_NODE" ]; then
    AKASH_NODE=$(curl -s "$AKASH_NET/rpc-nodes.txt" | shuf -n 1)
    echo "📡 AKASH_NODE not set — selected random: $AKASH_NODE"
  else
    echo "📡 AKASH_NODE already set: $AKASH_NODE"
  fi
  sleep 1.5

  # ✅ Get AKASH wallet address
  if provider-services keys show "$AKASH_KEY_NAME" --keyring-backend "$AKASH_KEYRING_BACKEND" >/dev/null 2>&1; then
    export AKASH_ACCOUNT_ADDRESS=$(provider-services keys show "$AKASH_KEY_NAME" --keyring-backend "$AKASH_KEYRING_BACKEND" -a)
    echo "✅ Found Akash account for key '$AKASH_KEY_NAME': $AKASH_ACCOUNT_ADDRESS"
  else
    echo "❌ No Akash account found with key name: $AKASH_KEY_NAME"
    echo "👉 Create one with: provider-services keys add $AKASH_KEY_NAME"
    exit 1.5
  fi
  sleep 1.5
  echo "🎉 Akash context configured!"
  sleep 2
}

#Checks if user has sufficient balance
check_balance() {
  while true; do
    echo "🔍 Checking your wallet balance..."
    sleep 1
    AKASH_BALANCE_RAW=$(provider-services query bank balances --node "$AKASH_NODE" "$AKASH_ACCOUNT_ADDRESS" -o json)
    UAKT_AMOUNT=$(echo "$AKASH_BALANCE_RAW" | jq -r '.balances[] | select(.denom=="uakt") | .amount')
    AKT_AMOUNT=$(awk -v amt="$UAKT_AMOUNT" 'BEGIN { printf "%.6f", amt / 1000000 }')

    echo "💰 You have $AKT_AMOUNT AKT"
    sleep 2

    if (( $(echo "$AKT_AMOUNT >= 5" | bc -l) )); then
      echo "✅ Balance is sufficient (≥ 5 AKT)."
      read -p "Do you want to continue? (y/N): " USER_CONFIRM
      if [[ "$USER_CONFIRM" != "y" ]]; then
        echo "❌ Aborting script."
        exit 1
      fi
      echo "🚀 Continuing..."
      break
    else
      echo -e "\n❌ A minimum of 5 AKT is required to proceed."
      echo "Please fund your wallet with at least 5 AKT."
      echo "Wallet Address: $AKASH_ACCOUNT_ADDRESS"
      echo ""
      echo "⏳ Waiting for you to fund your wallet..."
      echo -e "\n🔁 After funding your wallet, press ENTER to check your balance again."

    # Wait for ENTER before looping again
    read -p ""
    echo ""
    fi
  done
}

check_certificate() {
  echo "🔐 Checking if a valid certificate exists..."
  sleep 1

  AKASH_ACCOUNT_ADDRESS=$(provider-services keys show "$AKASH_KEY_NAME" -a)

  # Query for valid certificates
  VALID_CERT_RESULT=$(provider-services query cert list \
  --owner="${AKASH_ACCOUNT_ADDRESS}" \
  --state=valid \
  --node="$AKASH_NODE" \
  -o json)
  

  VALID_CERT_COUNT=$(echo "$VALID_CERT_RESULT" | jq -r '.certificates | length' 2>/dev/null)
  VALID_CERT_COUNT=${VALID_CERT_COUNT:-0}

  sleep 1

  if [ "$VALID_CERT_COUNT" -eq 0 ]; then
    echo "❌ No valid certificate found for: $AKASH_ACCOUNT_ADDRESS"
    echo "📋 A certificate is required to deploy workloads to Akash."
    read -p "Would you like to generate and publish a new certificate now? (y/N): " USER_CONFIRM

    if [[ "$USER_CONFIRM" != "y" ]]; then
      echo "❌ Aborting — cannot deploy without a valid certificate."
      exit 1
    fi

    echo "🛠️ Generating client certificate..."
    provider-services tx cert generate client --from="$AKASH_KEY_NAME" --keyring-backend="$AKASH_KEYRING_BACKEND" --force
    sleep 1

    echo "📤 Publishing certificate to the chain..."
    provider-services tx cert publish client --from="$AKASH_KEY_NAME" --chain-id="$AKASH_CHAIN_ID" --node="$AKASH_NODE" --yes --keyring-backend="$AKASH_KEYRING_BACKEND" --force
    sleep 1

    echo "✅ Certificate successfully generated and published!"
  else
    echo "✅ Valid certificate found for: $AKASH_ACCOUNT_ADDRESS"
    sleep 1
  fi
}

#CREATES DEPLOYMENT TO AKASH NETWORK AND SAVES RESULT TO BIN DIRECTORY
create_and_save_deployment() {
  mkdir ./bin
  DEPLOY_FILE="./deploy.processed.yml"
  DEPLOYMENT_JSON="./bin/deployment_result.json"

  # Skip if deployment already exists
  if [ -f "$DEPLOYMENT_JSON" ]; then
    DSEQ=$(jq -r '.logs[0].events[] | .attributes[] | select(.key=="dseq").value' "$DEPLOYMENT_JSON" | head -n1 | tr -d '\n')
    echo "⚠️ Deployment already exists with DSEQ: $DSEQ"
    #MAYBE ASK IF THEY WANT TO CONTINUE WITH THEIR DEPLOYMENT
  else
    echo "🚀 Submitting deployment from $DEPLOY_FILE..."
    DEPLOY_RESULT=$(provider-services tx deployment create "$DEPLOY_FILE" --from "$AKASH_KEY_NAME" --node "$AKASH_NODE" -y -o json)

    # Save formatted JSON to file
    echo "$DEPLOY_RESULT" | jq '.' > "$DEPLOYMENT_JSON"

    # Extract DSEQ
    DSEQ=$(echo "$DEPLOY_RESULT" | jq -r '.logs[0].events[] | .attributes[] | select(.key=="dseq").value' | head -n1 | tr -d '\n')

    if [ -z "$DSEQ" ]; then
      echo "❌ Deployment failed. No DSEQ found."
      return 1
    fi
  fi

  export DSEQ="$DSEQ" # Correctly export DSEQ
}


get_and_save_bids() {
  DEPLOYMENT_JSON="./bin/deployment_result.json"
  BIDS_JSON="bids.json"

  if [ ! -f "$DEPLOYMENT_JSON" ]; then
    echo "❌ Deployment result not found. Please deploy first."
    return 1
  fi

  if [ -z "$DSEQ" ]; then
    echo "❌ Could not extract DSEQ from deployment result."
    return 1
  fi

  echo "📡 Fetching bids for DSEQ: $DSEQ..."
  sleep 10
  BIDS_RESULT=$(provider-services query market bid list \
    --owner="$AKASH_ACCOUNT_ADDRESS" \
    --node="$AKASH_NODE" \
    --dseq="$DSEQ" \
    --state=open \
    -o json)

  echo "$BIDS_RESULT" | jq '.' > "$BIDS_JSON"
  
  # Check if any bids were returned
  BID_COUNT=$(echo "$BIDS_RESULT" | jq '.bids | length')
  if [ "$BID_COUNT" -eq 0 ]; then
    echo "⚠️ No bids found yet. Providers may still be responding."
    return 1
  fi

  echo "✅ Found $BID_COUNT open bid(s). Saved to $BIDS_JSON"
}


select_provider_from_bids() {
  echo "Fetching bids..."
  sleep 5
  local BIDS_JSON="bids.json"
  local PROVIDER
  local BLOCKS_PER_MONTH=425066  # Matches Akash Console estimate

  if [ ! -f "$BIDS_JSON" ]; then
    echo "❌ $BIDS_JSON not found."
    return 1
  fi
  
  if [ ! -f "$BIDS_JSON" ]; then
    echo "❌ $BIDS_JSON not found."
    return 1
  fi

  jq -r '.bids[].bid | "\(.bid_id.provider)|\(.price.amount)"' "$BIDS_JSON" > ./bin/provider_list.tmp

  if [ ! -s ./bin/provider_list.tmp ]; then
    echo "⚠️ No bids found in $BIDS_JSON"
    rm -f ./bin/provider_list.tmp
    return 1
  fi

  echo "🔍 Available Providers:"
  echo

  i=0
  provider_array=()
  while IFS='|' read -r address uakt_price; do
  monthly_price=$(echo "scale=6; ($uakt_price * $BLOCKS_PER_MONTH) / 1000000" | bc)

  echo "[$i] Provider: $address"
  echo "    💰 Monthly Price: ≈ ${monthly_price} AKT"
  echo
  provider_array[$i]="$address"
  i=$((i + 1))
  done < ./bin/provider_list.tmp
  if [provider_array length == 0]; then
      exit 1
  fi
  # Ask user for input
  read -p "👉 Select a provider [0-$((${#provider_array[@]} - 1))]: " choice

  # Validate input and save selection
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 0 ] && [ "$choice" -lt "${#provider_array[@]}" ]; then
    PROVIDER="${provider_array[$choice]}"
    export AKASH_PROVIDER="$PROVIDER"
    echo "✅ Selected Provider: $PROVIDER"
  else
    echo "❌ Invalid selection."
    return 1
  fi
  create_lease
}


create_lease() {
  local DEPLOYMENT_JSON="./bin/deployment_result.json"

  if [ ! -f "$DEPLOYMENT_JSON" ]; then
    echo "❌ Deployment result not found at $DEPLOYMENT_JSON"
    return 1
  fi

  if [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ AKASH_PROVIDER not set. Please select a provider first."
    return 1
  fi

  
  if [ -z "$DSEQ" ]; then
    echo "❌ Failed to extract DSEQ from deployment result."
    return 1
  fi

  echo "🔐 Creating lease for DSEQ: $DSEQ, Provider: $AKASH_PROVIDER"

  provider-services tx market lease create \
    --dseq "$DSEQ" \
    --provider "$AKASH_PROVIDER" \
    --from "$AKASH_KEY_NAME" \
    --node "$AKASH_NODE" \
    -y

  if [ $? -eq 0 ]; then
    echo "✅ Lease successfully created!"
    rm bids.json
  else
    echo "❌ Failed to create lease."
    return 1
  fi
  send_manifest
}


send_manifest() {
  DEPLOY_FILE="./deploy.processed.yml"
  DEPLOYMENT_JSON="./bin/deployment_result.json"

  
  if [ -z "$DSEQ" ] || [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ Missing DSEQ or AKASH_PROVIDER"
    return 1
  fi

  echo "📤 Sending manifest to provider..."
  provider-services send-manifest "$DEPLOY_FILE" \
    --dseq "$DSEQ" \
    --provider "$AKASH_PROVIDER" \
    --from "$AKASH_KEY_NAME" \
    --node "$AKASH_NODE"

  if [ $? -eq 0 ]; then
    echo "✅ Manifest successfully sent!"
  else
    echo "❌ Failed to send manifest."
    return 1
  fi
  get_service_url
}


get_service_url() {
  DEPLOYMENT_JSON="./bin/deployment_result.json"

  if [ -z "$DSEQ" ] || [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ Missing DSEQ or AKASH_PROVIDER"
    return 1
  fi

  echo "🔎 Fetching deployment status and URL..."

  while true; do
    STATUS=$(provider-services lease-status --dseq "$DSEQ" --from "$AKASH_KEY_NAME" --provider "$AKASH_PROVIDER" 2>/dev/null)
    echo "$STATUS" > ./bin/lease_status.json

    PROXY_URI=$(echo "$STATUS" | jq -r '.services["nfa-proxy"].uris[0] // empty')
    CONSUMER_URI=$(echo "$STATUS" | jq -r '.services["consumer-node"].uris[0] // empty')

    if [[ -n "$PROXY_URI" && -n "$CONSUMER_URI" ]]; then
      echo "✅ nfa-proxy URL: https://$PROXY_URI"
      echo "✅ consumer-node URL: https://$CONSUMER_URI"

      echo "https://$PROXY_URI" > ./bin/proxy-url.txt
      echo "https://$CONSUMER_URI" > ./bin/consumer-url.txt
      break
    else
      echo "⚠️ Deployment not ready. Waiting for URIs... Retrying in 10 seconds."
      sleep 10
    fi
  done

}






deploy_to_akash

