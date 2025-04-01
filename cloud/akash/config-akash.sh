#!/bin/bash


#AKASH NETWORK CONFIGURATION
export AKASH_NET="https://raw.githubusercontent.com/akash-network/net/main/mainnet"
export AKASH_VERSION="$(curl -s https://api.github.com/repos/akash-network/provider/releases/latest | jq -r '.tag_name')"
export AKASH_CHAIN_ID="$(curl -s "$AKASH_NET/chain-id.txt")"
export AKASH_NODE="$(curl -s "$AKASH_NET/rpc-nodes.txt" | shuf -n 1)"
export AKASH_KEYRING_BACKEND=os

#AKASH BID CONFIGURATION
export AKASH_GAS=auto
export AKASH_GAS_ADJUSTMENT=1.5
export AKASH_GAS_PRICES=0.025uakt
export AKASH_SIGN_MODE=amino-json


# Deployment function
deploy_to_akash() {
  set -e

  # Validates Akash cli installation
  check_akash
  #setup
  setup
  # Checks cli dependencies. 
  check_dependencies
  # Akash keys menu
  keys_menu  
  # Open deployment menu
  select_deployment_menu
  # bids menu for deployment
  select_bid
  # On chain agreement between provider and you
  create_lease
  # Submit nmanifest to provider
  send_manifest
  # Gets updated URL. 
  get_service_url
  # Update configuration with URLs.
  update_configuration
}

setup() {
  BIN_ROOT="$(pwd)/bin"
  HAS_BIN=false
  HAS_KEYS=false
  HAS_DEPLOYMENTS=false
  # Ensure bin directory exists
  if [ ! -d "$BIN_ROOT" ]; then
    mkdir -p "$BIN_ROOT"
    echo "making bin directory"
     
  fi
  HAS_BIN=true
 

  # Check if any Akash keys exist using the CLI
  KEY_LIST=$(provider-services keys list --keyring-backend os 2>/dev/null)

  # Extract key names from the list
  KEY_NAMES=($(echo "$KEY_LIST" | awk '/^- name:/ {print $3}'))

  # Set HAS_KEYS=true if we found any keys
  if [ ${#KEY_NAMES[@]} -gt 0 ]; then
    HAS_KEYS=true
  else
    HAS_KEYS=false
  fi


  # Check if any key dir has deployments
  if [ "$HAS_KEYS" = true ]; then
    for key_path in "${KEY_DIRS[@]}"; do
      DSEQ_DIRS=($(find "$key_path" -mindepth 1 -maxdepth 1 -type d))
      if [ ${#DSEQ_DIRS[@]} -gt 0 ]; then
        HAS_DEPLOYMENTS=true
        break
      fi
    done
  fi

  # Export the state flags
  export HAS_BIN
  export HAS_KEYS
  export HAS_DEPLOYMENTS
}

# Ensures user has homebrew and akash cli installed
check_akash() {
  # Check for Internet
  if ! ping -c 1 github.com >/dev/null 2>&1; then
    echo "❌ No internet connection. Cannot proceed."
    exit 1
  fi

  # Check if both tools are installed
  if command -v akash >/dev/null && command -v provider-services >/dev/null; then
    echo "✅ Akash CLI and provider-services already installed."
    return
  else
    echo "❌ Akash CLI and/or provider-services not found."
    read -rp "❓ Would you like to install them now? (y/n): " INSTALL_AKASH
    [[ "$INSTALL_AKASH" =~ ^[Yy]$ ]] || { echo "🚫 Installation canceled. Exiting."; exit 1; }
  fi

  # Ensure Homebrew is installed
  if ! command -v brew >/dev/null; then
    echo "🍺 Homebrew is required but not installed."

    read -rp "❓ Install Homebrew? (y/n): " INSTALL_BREW
    [[ "$INSTALL_BREW" =~ ^[Yy]$ ]] || { echo "🚫 Cannot continue without Homebrew. Exiting."; exit 1; }

    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      echo "❌ Homebrew installation failed. Try manually from https://brew.sh"
      exit 1
    }

    # Update PATH
    [[ -d "/opt/homebrew/bin" ]] && export PATH="/opt/homebrew/bin:$PATH"
    [[ -d "/usr/local/bin" ]] && export PATH="/usr/local/bin:$PATH"
  fi

  # Install Akash and provider-services
  echo "📦 Installing Akash CLI tools via Homebrew..."
  brew tap akash-network/tap
  brew install akash || { echo "❌ Failed to install akash."; exit 1; }
  brew install akash-provider-services || { echo "❌ Failed to install provider-services."; exit 1; }

  echo "✅ Akash CLI and provider-services installed successfully."
  echo "🔧 Version: $(akash version)"
}

check_dependencies() {
  echo "🔎 Checking required dependencies..."
  sleep 1

  OS_TYPE=$(uname -s)
  SHUF_CMD="shuf"

  if [[ "$OS_TYPE" == "Darwin" ]]; then
    # macOS needs gshuf (from coreutils)
    SHUF_CMD="gshuf"
    if ! command -v "$SHUF_CMD" >/dev/null 2>&1; then
      echo "📦 Installing gshuf (coreutils) for macOS..."
      brew install coreutils
    fi
  fi

  REQUIRED_CMDS=(bash akash curl jq awk sed bc grep tr head mkdir read sleep echo gum "$SHUF_CMD")
  MISSING_CMDS=()

  for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      MISSING_CMDS+=("$cmd")
    fi
  done

  if [ "${#MISSING_CMDS[@]}" -eq 0 ]; then
    echo "✅ All dependencies are installed."
    return
  fi

  echo -e "\n❌ Missing dependencies: ${MISSING_CMDS[*]}"
  for cmd in "${MISSING_CMDS[@]}"; do
    echo "📦 Installing $cmd..."
    brew install "$cmd"
  done
}

keys_menu() {
  # If no keys exist at all
  if [ "$HAS_KEYS" = false ]; then
    echo "⚠️ No Akash wallets found."
    create_new_key_menu
    return
  fi

  # Fetch key names from provider-services
  KEY_NAMES=($(provider-services keys list | awk '/^- name:/ { print $3 }'))


  OPTIONS=("${KEY_NAMES[@]}" "Create New Wallet")

  SELECTED_KEY=$(printf "%s\n" "${OPTIONS[@]}" | gum choose --header="🔐 Select a wallet or create a new one" --cursor="👉")

  if [ "$SELECTED_KEY" == "Create New Wallet" ]; then
    CREATE_NEW_KEY=true
    create_new_key_menu
  else
    export AKASH_KEY_NAME="$SELECTED_KEY"
    echo "✅ Using wallet: $AKASH_KEY_NAME"
    export AKASH_ACCOUNT_ADDRESS="$(provider-services keys show $AKASH_KEY_NAME -a)"
    mkdir -p "./bin/$AKASH_KEY_NAME"
  fi
}
#helper, do not call
create_new_key_menu() {
  ACTION=$(gum choose --header="🧠 How would you like to create your wallet?" --cursor="👉" "🆕 Create Fresh Wallet" "📥 Import Existing Wallet")

  case "$ACTION" in
    "🆕 Create Fresh Wallet")
      read -rp "🔑 Enter a name for your new wallet key: " AKASH_KEY_NAME
      provider-services keys add "$AKASH_KEY_NAME" --keyring-backend os
      echo -e "\n📄 Save your mnemonic phrase safely. Fund your wallet with at least 5 AKT before continuing."
      read -rp "⏸️ Press Enter to continue..."
      ;;
    "📥 Import Existing Wallet")
      read -rp "🔑 Enter a name for your wallet key: " AKASH_KEY_NAME
      read -rp "🧠 Paste your 24-word mnemonic: " MNEMONIC
      echo "$MNEMONIC" | provider-services keys add "$AKASH_KEY_NAME" --recover --keyring-backend os
      echo "✅ Wallet imported: $AKASH_KEY_NAME"
      ;;
    *)
      echo "❌ Invalid selection. Exiting."
      exit 1
      ;;
  esac

  export AKASH_KEY_NAME
  mkdir -p "./bin/$AKASH_KEY_NAME"
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

    if (( $(echo "$AKT_AMOUNT >= 0.5" | bc -l) )); then
      echo "✅ Balance is sufficient (≥ 0.5 AKT)."
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




select_deployment_menu() {
  local WALLET_ADDRESS
  WALLET_ADDRESS=$(provider-services keys show "$AKASH_KEY_NAME" -a)

  echo "🔍 Checking for active deployments for key: $AKASH_KEY_NAME..."

  local DSEQ_LIST_RAW
  DSEQ_LIST_RAW=$(provider-services query deployment list --owner "$WALLET_ADDRESS" --state active -o json | jq -r '.deployments[].deployment.deployment_id.dseq')

  if [[ -z "$DSEQ_LIST_RAW" ]]; then
  echo "ℹ️ No active deployments found."
  echo "🚀 Proceeding to create a new deployment..."
  handle_new_deployment
  return
  fi

  local DSEQ_ARRAY=()
  local OPTIONS=()

  while IFS= read -r dseq_raw; do
    # Validate it's a uint
    if [[ "$dseq_raw" =~ ^[0-9]+$ ]]; then
      DSEQ_ARRAY+=("$dseq_raw")
      OPTIONS+=("📦 DSEQ $dseq_raw")
    fi
  done <<< "$DSEQ_LIST_RAW"

  # Add "new deployment" option
  OPTIONS+=("➕ Create new deployment")

  # Show menu
  echo
  local SELECTED
  SELECTED=$(gum choose "${OPTIONS[@]}" --header="📂 Active Deployments for $AKASH_KEY_NAME")

  # Handle selection
  if [[ "$SELECTED" == "➕ Create new deployment" ]]; then
    handle_new_deployment
  else
    # Extract DSEQ from selection and validate it’s in the array
    SELECTED_DSEQ=$(echo "$SELECTED" | grep -oE '[0-9]+')

    if [[ " ${DSEQ_ARRAY[*]} " =~ " $SELECTED_DSEQ " ]]; then
      export DSEQ="$SELECTED_DSEQ"
      handle_existing_deployment "$DSEQ"
    else
      echo "❌ Invalid selection. No matching DSEQ found."
      return 1
    fi
  fi
}
#helper for select_deployment_menu
handle_existing_deployment() {
  local DSEQ="$1"
  echo $DSEQ

  echo
  local ACTION
  ACTION=$(gum choose "🔁 Update deployment" "❌ Delete deployment" "⬅️ Go back" --header="Manage DSEQ $DSEQ")

  case "$ACTION" in
    "🔁 Update deployment (Does nothing atm)")
      echo "🔧 Updating deployment $DSEQ..."
      update_deployment "$DSEQ"
      ;;
    "❌ Delete deployment")
      close_deployment "$DSEQ"
      select_deployment_menu
      ;;
    "⬅️ Go back")
      select_deployment_menu
      ;;
  esac
}
#helper for select_deployment_menu
handle_new_deployment() {
  echo
  gum confirm "Creating a new deployment requires signing a transaction. Continue?" && {
    

    echo "🚀 Starting new deployment for key: $AKASH_KEY_NAME"
    
    # This function will:
    # - Run deployment tx
    # - Capture DSEQ
    # - Create folder: bin/$AKASH_KEY_NAME/$DSEQ/
    # - Save lease.json, processed YAML, etc.
    check_certificate
    check_balance
    init_new_deployment_flow
  } || {
    echo "❌ New deployment cancelled."
    exit 1
  }
}
#helper
init_new_deployment_flow() {
  ./process-yml.sh

  echo "🚀 Broadcasting deployment transaction..."
  DEPLOY_OUTPUT=$(provider-services tx deployment create deploy.processed.yml --from "$AKASH_KEY_NAME" -o json)

  # Handle CLI error
  if echo "$DEPLOY_OUTPUT" | grep -q "^Error:"; then
    echo "❌ Deployment failed:"
    echo "$DEPLOY_OUTPUT"
    exit 1
  fi

  # Validate JSON
  if ! echo "$DEPLOY_OUTPUT" | jq . >/dev/null 2>&1; then
    echo "❌ Deployment output is not valid JSON:"
    exit 1
  fi

  # Extract DSEQ
  DSEQ=$(echo "$DEPLOY_OUTPUT" | jq -r '.body.messages[0].id.dseq' | grep -Eo '^[0-9]+$')
  export DSEQ

  if [[ -z "$DSEQ" || "$DSEQ" == "null" ]]; then
    echo "❌ Failed to extract DSEQ from deployment result."
    exit 1
  fi

  echo "📁 Creating folder: bin/$AKASH_KEY_NAME/$DSEQ"
  mkdir -p "bin/$AKASH_KEY_NAME/$DSEQ"

  echo "$DEPLOY_OUTPUT" > "bin/$AKASH_KEY_NAME/$DSEQ/result.json"
  echo "{\"dseq\": \"$DSEQ\", \"key\": \"$AKASH_KEY_NAME\"}" > "bin/$AKASH_KEY_NAME/$DSEQ/lease.json"
  cp deploy.processed.yml "bin/$AKASH_KEY_NAME/$DSEQ/deploy.processed.yml"

  echo "✅ Deployment created and stored — DSEQ: $DSEQ"
}

##############################
select_bid() {
  echo "🛰️ Grabbing open bids for DSEQ: $DSEQ"
  sleep 1

  if [[ -z "$DSEQ" ]]; then
    echo "❌ DSEQ is not set."
    return 1
  fi

  local attempt=1
  local max_attempts=3
  local BLOCKS_PER_MONTH
  BLOCKS_PER_MONTH=$(echo "scale=0; (86400 / 6.098) * 30" | bc)

  while [ $attempt -le $max_attempts ]; do
    echo "📡 Attempt $attempt: Fetching bids..."
    sleep 5

    local BIDS_JSON
    BIDS_JSON=$(provider-services query market bid list \
      --owner="$AKASH_ACCOUNT_ADDRESS" \
      --node="$AKASH_NODE" \
      --dseq="$DSEQ" \
      --state=open \
      --output json)

    local BID_COUNT
    BID_COUNT=$(echo "$BIDS_JSON" | jq '.bids | length')

    if [[ "$BID_COUNT" -gt 0 ]]; then
      echo "✅ Found $BID_COUNT open bid(s)."

      local BID_ENTRIES=()

      # Build structured list of bids (provider + monthly amount)
      while IFS='|' read -r PROVIDER PRICE; do
        MONTHLY=$(echo "scale=6; $PRICE * $BLOCKS_PER_MONTH / 1000000" | bc)
        BID_ENTRIES+=("{\"provider\":\"$PROVIDER\",\"monthly\":\"$MONTHLY\"}")
      done < <(echo "$BIDS_JSON" | jq -r '.bids[].bid | "\(.bid_id.provider)|\(.price.amount)"')

      if [[ ${#BID_ENTRIES[@]} -eq 0 ]]; then
        echo "❌ No valid bids found after parsing."
        return 1
      fi

      # Pass structured entries to menu
      render_bid_menu "${BID_ENTRIES[@]}"
      return $?
    fi

    echo "⏳ No bids found. Retrying in 10s..."
    sleep 10
    attempt=$((attempt + 1))
  done

  echo "❌ No valid bids received after $max_attempts attempts."
  return 1
}
# helper
render_bid_menu() {
  local entries=("$@")
  local OPTIONS=()

  echo "📋 Rendering provider menu..."
  for entry in "${entries[@]}"; do
    local PROVIDER=$(echo "$entry" | jq -r '.provider')
    local MONTHLY=$(echo "$entry" | jq -r '.monthly')
    OPTIONS+=("💸 ${MONTHLY} AKT/mo — ${PROVIDER}")
  done

  # Prompt user
  local SELECTED_INDEX
  SELECTED_INDEX=$(printf '%s\n' "${OPTIONS[@]}" | nl -w1 -s': ' | gum choose --header="🔻 Select Provider")

  if [[ -z "$SELECTED_INDEX" ]]; then
    echo "❌ No provider selected."
    return 1
  fi

  # Extract the index (before ":")
  local INDEX=$(echo "$SELECTED_INDEX" | cut -d':' -f1)
  local RAW_ENTRY="${entries[$((INDEX - 1))]}"

  export AKASH_PROVIDER=$(echo "$RAW_ENTRY" | jq -r '.provider')
  echo "✅ Selected provider address: $AKASH_PROVIDER"
}

create_lease() {

  if [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ AKASH_PROVIDER not set. Please select a provider first."
    select_bid
  fi

  
  if [ -z "$DSEQ" ]; then
    echo "❌ Failed to extract DSEQ"
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
  else
    echo "❌ Failed to create lease."
    return 1
  fi
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
}

###############################

get_service_url() {

  if [ -z "$DSEQ" ] || [ -z "$AKASH_PROVIDER" ]; then
    echo "❌ Missing DSEQ or AKASH_PROVIDER"
    return 1
  fi

  echo "🔎 Fetching deployment status and URL..."
  sleep 5

  while true; do
    STATUS=$(provider-services lease-status --dseq "$DSEQ" --from "$AKASH_KEY_NAME" --provider "$AKASH_PROVIDER" 2>/dev/null)

    PROXY_URI=$(echo "$STATUS" | jq -r '.services["nfa-proxy"].uris[0] // empty')
    CONSUMER_URI=$(echo "$STATUS" | jq -r '.services["consumer-node"].uris[0] // empty')
    
    if [[ -n "$PROXY_URI" && -n "$CONSUMER_URI" ]]; then
      echo "✅ nfa-proxy URL: https://$PROXY_URI"
      echo "✅ consumer-node URL: https://$CONSUMER_URI"
      
      export NFA_PROXY_URL="https://$PROXY_URI"
      export CONSUMER_URL="https://$CONSUMER_URI"

      break
    else
      echo "⚠️ Deployment not ready. Waiting for URIs... Retrying in 10 seconds."
      sleep 10
    fi
  done
}
update_configuration() {
  LOCAL_PATH="./bin/${AKASH_KEY_NAME}/${DSEQ}/"
  echo "🔧 Processing deployment config..."
  # Update PROXY_URL with trailing `/v1`
  sed -i.bak "s|^      - PROXY_URL=.*|      - PROXY_URL=${NFA_PROXY_URL}/v1|" ${LOCAL_PATH}/deploy.processed.yml

  # Update CONSUMER_NODE_URL
  sed -i.bak "s|^      - CONSUMER_NODE_URL=.*|      - CONSUMER_NODE_URL=${CONSUMER_URL}|" ${LOCAL_PATH}/deploy.processed.yml


  if [ -z "$DSEQ" ]; then
    echo "❌ DSEQ not found. Make sure deployment_result.json exists and is valid."
    return 1
  fi

  echo "📦 Submitting deployment update..."
  provider-services tx deployment update ${LOCAL_PATH}/deploy.processed.yml --dseq "$DSEQ" --from "$AKASH_KEY_NAME"

  echo "🚀 Sending updated manifest to provider..."
  provider-services send-manifest ${LOCAL_PATH}deploy.processed.yml --dseq "$DSEQ" --provider "$AKASH_PROVIDER" --from "$AKASH_KEY_NAME"

  echo "✅ Deployment updated with new environment variables."
  sleep 1
  echo "Please insert your ETH wallet private key through the akash cli in the update tab. Be sure to connect the same wallet you used to the akash console."
  sleep 0.5
}


################  UTILS  ############### 


# Takes DSEQ PARAM
wait_for_deployment() {
  local dseq="$1"
  local attempts=0
  local max_attempts=5
  local delay=2

  echo "⏳ Waiting for deployment $dseq to propagate..."
  wait 1

  while [[ $attempts -lt $max_attempts ]]; do
    provider-services query deployment get \
      --owner "$AKASH_ACCOUNT_ADDRESS" \
      --dseq "$dseq" >/dev/null 2>&1

    if [[ $? -eq 0 ]]; then
      echo "✅ Deployment $dseq found on chain!"
      return 0
    fi

    echo "🔁 Retry $((attempts + 1)) — not found yet. Retrying in ${delay}s..."
    sleep "$delay"
    attempts=$((attempts + 1))
  done

  echo "❌ Deployment $dseq not found after $max_attempts attempts."
  return 1
}

# Takes DSEQ PARAM
close_deployment() {
  local DSEQ="$1"
  local DEPLOY_DIR="bin/$AKASH_KEY_NAME/$DSEQ"

  echo "🛑 Closing deployment $DSEQ..."
  sleep 1

  if provider-services tx deployment close --from "$AKASH_KEY_NAME" --dseq "$DSEQ"; then
    echo "✅ Deployment $DSEQ closed."

    if [ -d "$DEPLOY_DIR" ]; then
      echo "🧹 Removing local folder: $DEPLOY_DIR"
      rm -rf "$DEPLOY_DIR"
    else
      echo "ℹ️ No local folder found for DSEQ $DSEQ"
    fi
  else
    echo "❌ Failed to close deployment $DSEQ."
    return 1
  fi
}

#ignore
estimate_blocks_per_month() {
  local status_json
  status_json=$(provider-services query status 2>/dev/null)
  local latest_time_raw=$(echo "$status_json" | jq -r '.SyncInfo.latest_block_time // empty')
  local latest_height=$(echo "$status_json" | jq -r '.SyncInfo.latest_block_height // empty')

  if [[ -z "$latest_time_raw" || -z "$latest_height" ]]; then
    echo "⚠️ Could not fetch block info. Defaulting to 432000 (approx 30d)."
    echo 432000
    return
  fi

  local past_height=$((latest_height - 1000))
  local past_time_raw=$(provider-services query block "$past_height" | jq -r '.block.header.time // empty')

  if [[ -z "$past_time_raw" ]]; then
    echo "⚠️ Could not fetch historical block time. Defaulting to 432000."
    echo 432000
    return
  fi

  local latest_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$latest_time_raw" +"%s" 2>/dev/null)
  local past_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$past_time_raw" +"%s" 2>/dev/null)

  if [[ -z "$latest_epoch" || -z "$past_epoch" ]]; then
    echo "⚠️ Timestamp conversion failed. Defaulting to 432000."
    echo 432000
    return
  fi

  local avg_time=$(echo "scale=4; ($latest_epoch - $past_epoch) / 1000" | bc)
  echo $(echo "scale=0; (30 * 24 * 3600) / $avg_time" | bc)
}







############################################

deploy_to_akash


