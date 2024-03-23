#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
# Copyright (C) 2018-2020 The PixelExperience Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

export DEVICE=beckham
export VENDOR=motorola

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        # Correct mods gid
        system/etc/permissions/com.motorola.mod.xml)
            sed -i "s|mot_mod|oem_5020|g" "${2}"
            ;;
        # Add uhid group for fingerprint service
        vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc)
            sed -i "s/system input/system uhid input/" "${2}"
            ;;
        # Add input group for adspd service
        vendor/etc/init/motorola.hardware.audio.adspd@1.0-service.rc)
            sed -i "s/media/media input/" "${2}"
            ;;
        # Replace libcutils with libprocessgroup
        vendor/lib/hw/audio.primary.sdm660.so)
            "${PATCHELF}" --replace-needed "libcutils.so" "libprocessgroup.so" "${2}"
            ;;
        # Fix camera recording
        vendor/lib/libmmcamera2_pproc_modules.so)
            sed -i "s/ro.product.manufacturer/ro.product.nopefacturer/" "${2}"
            ;;
        # Load ZAF configs from vendor
        vendor/lib/libzaf_core.so)
            sed -i "s|/system/etc/zaf|/vendor/etc/zaf|g" "${2}"
            ;;
        # Use VNDK 32 libutils
        vendor/lib/hw/audio.primary.sdm660.so | vendor/lib/libaudioroute.so | vendor/lib/libmotaudioutils.so | vendor/lib/libsensorndkbridge.so |vendor/lib/libtinyalsa.so | vendor/lib/libtinycompress.so | vendor/lib/libtinycompress_vendor.so |vendor/lib/libunshorten.so)
            "${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
            ;;
        vendor/lib/soundfx/libspeakerbundle.so | vendor/lib/soundfx/libmmieffectswrapper.so | vendor/lib/libeqservicebridge.so | vendor/lib/motorola.hardware.audio.eqservice@1.0_vendor.so)
            "${PATCHELF}" --replace-needed "libutils.so" "libutils-v32.so" "${2}"
            ;;
        # Fix missing symbols
        vendor/lib/libmot_gpu_mapper.so)
            for LIBGUI_SHIM in $(grep -L "libgui_shim_vendor.so" "${2}"); do
                "${PATCHELF}" --add-needed "libgui_shim_vendor.so" "${LIBGUI_SHIM}"
            done
            ;;
        # Load wrapped shim
        vendor/lib64/libmdmcutback.so)
             "${PATCHELF}" --replace-needed "libqsap_sdk.so" "libqsap_shim.so" "${2}"
            ;;
        # memset shim
        vendor/bin/charge_only_mode)
            for  LIBMEMSET_SHIM in $(grep -L "libmemset_shim.so" "${2}"); do
                "${PATCHELF}" --add-needed "libmemset_shim.so" "$LIBMEMSET_SHIM"
            done
            ;;
    esac
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}"/proprietary-files.txt "${SRC}" \
	"${KANG}" --section "${SECTION}"
extract "${MY_DIR}"/proprietary-files-qc.txt "$SRC" \
	"${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
