#!/bin/bash

# Source secrets if available
if [ -f "$HOME/.secrets" ]; then
    source "$HOME/.secrets"
elif [ -f "$(pwd)/.secrets" ]; then
    source "$(pwd)/.secrets"
else
    echo "⚠️ Warning: .secrets file not found in $HOME or $(pwd)"
fi

# =========================================================
# CONFIGURATION (LG V60 ThinQ - timelm / Android 16.2)
# =========================================================
DEVICE_CODE="timelm"
BUILD_TARGET="DerpFest"
ANDROID_VERSION="16.2"

export TZ="Asia/Jakarta"
export BUILD_USERNAME="s0711482299"
export BUILD_HOSTNAME="crave-builder"
export USE_CCACHE=0

# =========================================================
# TELEGRAM FUNCTIONS
# =========================================================

send_telegram() {
  local chat_id="$1"
  local message="$2"
  local _TK="$TG_BOT_TOKEN"

  if [ -z "$_TK" ] || [ -z "$chat_id" ]; then
    echo "⚠️ Telegram credentials missing. Skipping notification."
    return 0
  fi

  local escaped_message
  escaped_message=$(echo "$message" | sed \
    -e 's/\*/\*TEMP\*/g' \
    -e 's/_/\_TEMP\_/g' \
    -e 's/\[/\\[/g' -e 's/\]/\\]/g' \
    -e 's/(/\\(/g' -e 's/)/\\)/g' \
    -e 's/~/\\~/g' -e 's/`/\\`/g' \
    -e 's/>/\\>/g' -e 's/#/\\#/g' \
    -e 's/+/\\+/g' -e 's/-/\\-/g' \
    -e 's/=/\\=/g' -e 's/|/\\|/g' \
    -e 's/{/\\{/g' -e 's/}/\\}/g' \
    -e 's/\./\\./g' -e 's/!/\\!/g' \
    -e 's/\*TEMP\*/\*/g' \
    -e 's/\_TEMP\_/\_/g')

  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Sending Telegram message to ${chat_id}"
  curl -s -X POST "https://api.telegram.org/bot${_TK}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${escaped_message}" \
    -d "parse_mode=MarkdownV2" \
    -d "disable_web_page_preview=true" > /dev/null
}

send_telegram_file() {
  local chat_id="$1"
  local file_path="$2"
  local caption="$3"
  local _TK="$TG_BOT_TOKEN"

  if [ -z "$_TK" ] || [ -z "$chat_id" ]; then
    echo "⚠️ Telegram credentials missing. Skipping document upload."
    return 0
  fi

  if [ ! -f "$file_path" ]; then
    echo "Error: File $file_path not found!"
    return 1
  fi

  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Sending document to Telegram (${chat_id})"

  curl -s -X POST "https://api.telegram.org/bot${_TK}/sendDocument" \
    -F "chat_id=${chat_id}" \
    -F "document=@${file_path}" \
    -F "caption=${caption}" > /dev/null
}

format_duration() {
    local T=$1
    local H=$((T/3600))
    local M=$(( (T%3600)/60 ))
    local S=$((T%60))
    printf "%02d hours, %02d minutes, %02d seconds" $H $M $S
}

# =========================================================
# BUILD LOGIC FUNCTION
# =========================================================

start_build_process() {
    START_TIME=$(date +%s)

    local initial_msg="⚙️ *ROM Build Started!*
*ROM:* $BUILD_TARGET
*Android:* $ANDROID_VERSION
*Device:* $DEVICE_CODE \\(LG V60 ThinQ\\)
*Start Time:* $(date '+%Y-%m-%d %H:%M:%S %Z')"

    send_telegram "$TG_BUILD_CHAT_ID" "$initial_msg"
    echo "Build Started at $(date '+%Y-%m-%d %H:%M:%S')"

    # 1. Initialize DerpFest Android 16.2 Manifest
    echo "Initializing DerpFest 16.2 manifest..."
    repo init -u https://github.com/DerpFest-AOSP/android_manifest.git -b 16.2 --git-lfs --depth 1

    # 2. Clean up existing/stale LG V60 trees
    echo "Cleaning old LG V60 device repositories..."
    rm -rf device/lge/timelm \
           vendor/lge/timelm \
           kernel/lge/sm8250 \
           hardware/lge \
           out/target/product/timelm \
           .repo/local_manifests

    # 3. Create local_manifests directory and populate timelm.xml
    echo "Setting up local manifest for lineage-23.2 trees..."
    mkdir -p .repo/local_manifests
    cat <<'EOF' > .repo/local_manifests/timelm.xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <!-- Device trees -->
  <project name="s0711482299-lgtm/android_device_lge_timelm" path="device/lge/timelm" remote="github" revision="lineage-23.2" />
  <!-- Hardware -->
  <project name="s0711482299-lgtm/android_hardware_lge" path="hardware/lge" remote="github" revision="lineage-23.2" />
  <!-- Kernel -->
  <project name="s0711482299-lgtm/android_kernel_lge_sm8250" path="kernel/lge/sm8250" remote="github" revision="lineage-23.2" />
  <!-- Vendor -->
  <project name="s0711482299-lgtm/proprietary_vendor_lge_timelm" path="vendor/lge/timelm" remote="github" revision="lineage-23.2" />
</manifest>
EOF

    # 4. Sync Sources using Crave Resync
    echo "Syncing repositories..."
    /opt/crave/resync.sh

    # 5. Legacy library symlinks fix for build tools
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5 2>/dev/null || true
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/libtinfo.so.5 2>/dev/null || true

    echo "Tree setup complete."

    # 6. Environment Setup & Lunch
    . build/envsetup.sh
    echo "Setting lunch target for LG V60..."
    lunch derp_timelm-bp4a-userdebug || lunch derp_timelm-userdebug

    make installclean

    # 7. Execute Build
    echo "========================="
    echo "Starting ROM Compilation..."
    echo "========================="

    mka bacon 2>&1 | tee log.txt
    BUILD_STATUS=${PIPESTATUS[0]}

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_FORMATTED=$(format_duration $DURATION)

    if [[ $BUILD_STATUS -eq 0 ]]; then
        local status_icon="✅"
        local status_text="Success"
        LOG_FILE="log.txt"
    else
        local status_icon="❌"
        local status_text="Failure (Exit Code: $BUILD_STATUS)"
        LOG_FILE="out/error.log"
        [ ! -f "$LOG_FILE" ] && LOG_FILE="log.txt"
    fi

    # 8. Send Final Status to Telegram
    local final_msg="${status_icon} *Build Finished!*
*ROM:* $BUILD_TARGET
*Android:* $ANDROID_VERSION
*Device:* $DEVICE_CODE
*Duration:* $DURATION_FORMATTED
*Status:* $status_text"

    send_telegram "$TG_BUILD_CHAT_ID" "$final_msg"

    if [[ -f "$LOG_FILE" ]]; then
        send_telegram_file "$TG_BUILD_CHAT_ID" "$LOG_FILE" "Build Logs"
    else
        send_telegram "$TG_BUILD_CHAT_ID" "⚠️ Warning: Log file ${LOG_FILE} not found."
    fi

    # 9. Upload Artifacts on Success
    if [[ $BUILD_STATUS -eq 0 ]]; then
        echo "Build successful. Starting upload script..."
        rm -rf go-up*
        wget -q https://raw.githubusercontent.com/nekoshirro/tools-gofile/refs/heads/private/go-up
        chmod +x go-up
        ./go-up out/target/product/timelm/*.zip
    else
        echo "Build failed. Check error log."
        [ -f out/error.log ] && cat out/error.log
    fi
}

start_build_process
