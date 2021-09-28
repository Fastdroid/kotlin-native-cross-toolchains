#!/bin/bash
set -e
cd "$(dirname "$0")"
source config

# Install prebuilt libgcc CRT start files
CLANG_RESOURCE_DIR="$("$OUTPUT_DIR/bin/clang" --print-resource-dir)"
for target in "${CROSS_TARGETS[@]}"; do
    if [ -f "prebuilt-libgcc-crt/crt_$target.tar.gz" ]; then
        mkdir -p "$CLANG_RESOURCE_DIR/lib/$target"
        tar_extractor.py "prebuilt-libgcc-crt/crt_$target.tar.gz" -C "$CLANG_RESOURCE_DIR/lib/$target"
        if [[ -f "$CLANG_RESOURCE_DIR/lib/$target/libatomic.a" ]]; then
            mkdir -p "$OUTPUT_DIR/$target/lib" && mv "$CLANG_RESOURCE_DIR/lib/$target/libatomic.a" "$OUTPUT_DIR/$target/lib"
        fi
        normalized_triple=$("$OUTPUT_DIR/bin/$target-clang" --print-target-triple)
        if [[ "$normalized_triple" != "$target" ]]; then
            ln -sfn $target "$CLANG_RESOURCE_DIR/lib/$normalized_triple"
        fi
    fi
done

# Install prebuilt libc/SDK for some targets
declare -A APPLE_INSTALLED_SDK
unset MSVC_SDK_INSTALLED
for target in "${CROSS_TARGETS[@]}"; do
    if [[ $target == *"android"* ]]; then
        mkdir -p "$OUTPUT_DIR/$target/include" "$OUTPUT_DIR/$target/lib"
        tar_extractor.py "prebuilt-bionic/bionic-libs_$target.tar.gz" -C "$OUTPUT_DIR/$target/lib" --strip 1
        tar_extractor.py prebuilt-bionic/bionic-headers.tar.gz -C "$OUTPUT_DIR/$target/include" --strip 1
    elif [[ $target == *"-linux-gnu"* ]]; then
        mkdir -p "$OUTPUT_DIR/$target"
        tar_extractor.py prebuilt-glibc/glibc-${GLIBC_VERSION}_$target.tar.gz -C "$OUTPUT_DIR/$target" --strip 1
    elif [[ $target == *"apple"* ]]; then
        DARWIN_SDK_NAME=""
        case "$target" in
        *macosx*|*ios*-macabi*)
            DARWIN_SDK_NAME=MacOSX
            DARWIN_SDK_VERSION=$MACOSX_VERSION
            ;;
        *ios*-simulator*) 
            DARWIN_SDK_NAME=iPhoneSimulator 
            DARWIN_SDK_VERSION=$IOS_VERSION
            ;;
        *ios*) 
            DARWIN_SDK_NAME=iPhoneOS
            DARWIN_SDK_VERSION=$IOS_VERSION
            ;;
        *tvos*-simulator*) 
            DARWIN_SDK_NAME=AppleTVSimulator
            DARWIN_SDK_VERSION=$APPLE_TVOS_VERSION
            ;;
        *tvos*)
            DARWIN_SDK_NAME=AppleTVOS
            DARWIN_SDK_VERSION=$APPLE_TVOS_VERSION 
            ;;
        *watchos*-simulator*)
            DARWIN_SDK_NAME=WatchSimulator
            DARWIN_SDK_VERSION=$APPLE_WATCHOS_VERSION
            ;;
        *watchos*)
            DARWIN_SDK_NAME=WatchOS
            DARWIN_SDK_VERSION=$APPLE_WATCHOS_VERSION
            ;;    
        esac
        if [[ -z "$DARWIN_SDK_NAME" ]]; then
            continue
        fi

        if [[ -z "${APPLE_INSTALLED_SDK[$DARWIN_SDK_NAME]}" ]]; then
            DARWIN_SDK_DIR="$OUTPUT_DIR/$DARWIN_SDK_NAME-SDK"
            mkdir -p "$DARWIN_SDK_DIR"
            tar_extractor.py "prebuilt-darwin-sdk/${DARWIN_SDK_NAME}${DARWIN_SDK_VERSION}.sdk.tar.xz" -C "$DARWIN_SDK_DIR" --strip 1
            # Clean unused files
            rm -rf "$DARWIN_SDK_DIR/usr/share" || true
            rm -rf "$DARWIN_SDK_DIR/usr/bin" || true
            rm -rf "$DARWIN_SDK_DIR/usr/sbin" || true
            ln -sfn "usr/include" "$DARWIN_SDK_DIR/include"
            ln -sfn "usr/lib" "$DARWIN_SDK_DIR/lib"
            APPLE_INSTALLED_SDK[$DARWIN_SDK_NAME]=1
        fi
        ln -sfn "$DARWIN_SDK_NAME-SDK" "$OUTPUT_DIR/$target"
    elif [[ $target == *"msvc"* ]]; then
        if [[ -z "$MSVC_SDK_INSTALLED" ]]; then
            mkdir -p "$OUTPUT_DIR/MSVC-SDK/VC" "$OUTPUT_DIR/MSVC-SDK/Windows-SDK"
            tar_extractor.py "prebuilt-msvc-sdk/VC-$VC_VERSION.tar.gz" -C "$OUTPUT_DIR/MSVC-SDK/VC" --strip 1
            tar_extractor.py "prebuilt-msvc-sdk/WindowsSDK-$WINDOWS_SDK_VERSION.tar.gz" -C "$OUTPUT_DIR/MSVC-SDK/Windows-SDK" --strip 1
            # Fix permission becuase MSVC-SDK was extract from Windows filesystems
            chmod -R u+rwX,go+rX,go-w "$OUTPUT_DIR/MSVC-SDK"
            MSVC_SDK_INSTALLED=1
        fi
    fi
    if [[ $target == *"-linux-"* && $target != *"android"* ]]; then
        # Extract linux header
        mkdir -p "$OUTPUT_DIR/$target"
        kernel_arch=''
        case "$target" in
        riscv*) kernel_arch=riscv ;;
        mips*) kernel_arch=mips ;;
        aarch64*|arm64*) kernel_arch=arm64 ;;
        arm*) kernel_arch=arm ;;
        i*86*|x86*) kernel_arch=x86 ;;
        esac
        tar_extractor.py prebuilt-linux-header/linux-header-${LINUX_KERNEL_VERSION}_$kernel_arch.tar.gz -C "$OUTPUT_DIR/$target"
    fi
done