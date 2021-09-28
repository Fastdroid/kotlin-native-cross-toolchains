#!/bin/bash
set -e
cd "$(dirname "$0")"
source config
export PATH="$OUTPUT_DIR/bin:$PATH"

SOURCE_TARBALL=llvm-project-$LLVM_VERSION.src.tar.xz
BUILD_DIR=".build-libunwind"
(test -d $BUILD_DIR && rm -rf $BUILD_DIR) || true
mkdir -p $BUILD_DIR
tar_extractor.py "$SOURCE_DIR/$SOURCE_TARBALL" -C $BUILD_DIR --strip 1
cd $BUILD_DIR
apply_patch llvm-$LLVM_VERSION
cd libunwind

for target in "${CROSS_TARGETS[@]}"; do
    if [[ $target == *"apple"* || $target == *"msvc"* ]]; then
        # Apple: Use libunwind in the SDK
        # MSVC: Do not use it now
        continue
    fi
    mkdir build-$target && cd build-$target
    LIBUNWIND_CXXFLAGS=""
    if [[ $target == *"linux"* ]]; then
        LIBUNWIND_CXXFLAGS="$LIBUNWIND_CXXFLAGS -D__STDC_FORMAT_MACROS"
    fi

    CXXFLAGS="$LIBUNWIND_CXXFLAGS" "$__CMAKE_WRAPPER" $target .. \
        -DCMAKE_INSTALL_PREFIX="$OUTPUT_DIR/$target" \
        -DCMAKE_C_COMPILER_WORKS=1 \
        -DCMAKE_CXX_COMPILER_WORKS=1 \
        -DLIBUNWIND_ENABLE_SHARED=OFF
    cmake --build . --target install/strip -- -j$(cpu_count)
    cd ..
    # Copy header files
    cp include/libunwind.h include/__libunwind_config.h "$OUTPUT_DIR/$target/include"
    # Merge libunwind into compiler-rt builtins
    if [[ -f "$OUTPUT_DIR/$target/lib/libunwind.a" ]]; then
        builtins_lib="$("$OUTPUT_DIR/bin/$target-clang" -rtlib=compiler-rt -print-libgcc-file-name)"
        if [[ -f "$builtins_lib" ]]; then
            "$OUTPUT_DIR/bin/llvm-ar" qcsL "$builtins_lib" "$OUTPUT_DIR/$target/lib/libunwind.a"
        fi
    fi
done
