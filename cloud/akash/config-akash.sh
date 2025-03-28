#!/bin/bash

#AKASH ACCOUNT CONFIGURATION
export AKASH_KEY_NAME="myKey"
export AKASH_KEYRING_BACKEND=os
export AKASH_ACCOUNT_ADDRESS="$(provider-services keys show $AKASH_KEY_NAME -a)"

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

ensure_akash_context() {
  #CHECKS IF AKASH IS INSTALLED
  check_akash_version
  
  echo "🔧 Ensuring Akash context is set..."
  sleep 1.5


  
  # 🔐 AKASH_KEY_NAME
  AKASH_KEYS=$(provider-services keys list)
  if [ -z "$AKASH_KEY_NAME" ]; then
    AKASH_KEY_NAME="myDefaultKey"
    echo "🔐 AKASH_KEY_NAME not set — using default: $AKASH_KEY_NAME"
  else
    echo "🔐 AKASH_KEY_NAME already set: $AKASH_KEY_NAME"
  fi
  sleep 1.5

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

  # ✅ Check if AKASH key exists
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

#helper function for ensure_akash_context
check_akash_version() {
    # ───────────────────────────────────────────────
    # 🔍 Check if Akash CLI is installed
    # ───────────────────────────────────────────────

    if ! command -v akash >/dev/null 2>&1; then
        echo "❌ Akash CLI is not installed or not in your PATH."
        echo "👉 Please install it from: https://github.com/akash-network/node/releases"
        echo "   or use Homebrew: brew install akash"
    exit 1
    fi

    # Optionally show version info
    AKASH_VERSION_INSTALLED=$(akash version 2>/dev/null || echo "unknown")
    echo "✅ Akash CLI detected — version: $AKASH_VERSION_INSTALLED"
    sleep 2
}


ensure_user_not_broke() {
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
  --owner="$(provider-services keys show $AKASH_KEY_NAME -a)" \
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
    provider-services tx cert generate client --from="$AKASH_KEY_NAME" --keyring-backend="$AKASH_KEYRING_BACKEND"
    sleep 1

    echo "📤 Publishing certificate to the chain..."
    provider-services tx cert publish client --from="$AKASH_KEY_NAME" --chain-id="$AKASH_CHAIN_ID" --node="$AKASH_NODE" --yes --keyring-backend="$AKASH_KEYRING_BACKEND"
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
  echo "Finding bids"
  sleep 10
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

  # Extract DSEQ from deployment result
  DSEQ2=$(jq -r '.logs[0].events[] | select(.type=="akash.v1") | .attributes[] | select(.key=="dseq") | .value' "$DEPLOYMENT_JSON")
  
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
    export AKASH_DSEQ="$DSEQ"
  else
    echo "❌ Failed to create lease."
    return 1
  fi
}

send_manifest() {
  DEPLOY_FILE="./deploy.processed.yml"
  DEPLOYMENT_JSON="./bin/deployment_result.json"

  # Extract DSEQ from saved deployment
  DSEQ=$(jq -r '.logs[0].events[] | .attributes[] | select(.key=="dseq").value' "$DEPLOYMENT_JSON" | head -n1 | tr -d '\n')

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
}

get_service_url() {
  sleep 30
  DEPLOYMENT_JSON="./bin/deployment_result.json"
  DSEQ1=$(jq -r '.logs[0].events[] | .attributes[] | select(.key=="dseq").value' "$DEPLOYMENT_JSON" | head -n1 | tr -d '\n')

  if [ -z "$DSEQ" ] || [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ Missing DSEQ or AKASH_PROVIDER"
    return 1
  fi

  echo "🔎 Fetching deployment status and URL..."

  STATUS=$(provider-services lease-status \
    --dseq "$DSEQ" \
    --provider "$AKASH_PROVIDER" \
    --from "$AKASH_KEY_NAME" \
    --node "$AKASH_NODE")

  URI=$(echo "$STATUS" | jq -r '.services.web.uris[0] // empty')

  if [ -n "$URI" ]; then
    echo "✅ Deployed URL: https://$URI"
    echo "$URI" > deployed-url.txt
  else
    echo "⚠️ Deployment is not ready yet, no URI found."
  fi
}





ensure_akash_context
ensure_user_not_broke
check_certificate
./process-yaml.sh
create_and_save_deployment
get_and_save_bids
select_provider_from_bids
create_lease
send_manifest
get_service_url