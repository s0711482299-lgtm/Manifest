#!/bin/bash

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

    echo "================================================="
    echo "⚙️ Starting ROM Compilation"
    echo "ROM: $BUILD_TARGET"
    echo "Android: $ANDROID_VERSION"
    echo "Device: $DEVICE_CODE (LG V60 ThinQ)"
    echo "Start Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "================================================="

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

    # 4. Sync Sources (Crave Resync with Repo Sync Fallback)
    echo "Syncing repositories..."
    if [ -f "/opt/crave/resync.sh" ]; then
        echo "Found Crave resync script. Running /opt/crave/resync.sh..."
        /opt/crave/resync.sh
    else
        echo "⚠️ /opt/crave/resync.sh not found. Falling back to standard repo sync..."
        repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
    fi

    # 5. Verify source sync success
    if [ ! -f "build/envsetup.sh" ]; then
        echo "❌ Critical Error: Source tree failed to sync (build/envsetup.sh missing)."
        exit 1
    fi

    # 6. Legacy library symlinks fix for build tools
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libncurses.so.6 /usr/lib/x86_64-linux-gnu/libncurses.so.5 2>/dev/null || true
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libtinfo.so.6 /usr/lib/x86_64-linux-gnu/libtinfo.so.5 2>/dev/null || true

    echo "Tree setup complete."

    # 7. Environment Setup & Lunch
    . build/envsetup.sh
    echo "Setting lunch target for LG V60..."
    lunch derp_timelm-bp4a-userdebug || lunch derp_timelm-userdebug

    make installclean

    # 8. Execute Build
    echo "========================="
    echo "Starting ROM Compilation..."
    echo "========================="

    mka bacon 2>&1 | tee log.txt
    BUILD_STATUS=${PIPESTATUS[0]}

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_FORMATTED=$(format_duration $DURATION)

    echo "================================================="
    if [[ $BUILD_STATUS -eq 0 ]]; then
        echo "✅ Build Finished Successfully!"
    else
        echo "❌ Build Failed with exit code: $BUILD_STATUS"
    fi
    echo "ROM: $BUILD_TARGET"
    echo "Device: $DEVICE_CODE"
    echo "Duration: $DURATION_FORMATTED"
    echo "================================================="

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
