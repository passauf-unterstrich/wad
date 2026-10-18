#!/bin/zsh
# build-whisper.sh
# Übersetzt whisper.cpp (Vendor/whisper.cpp) zu statischen Bibliotheken, die Wad fest einbindet:
# nur macOS, Apple Silicon und Intel in einer Datei („Universal“), Grafikeinheit über Metal,
# Metal-Programme eingebettet. Einmal nach dem Klonen ausführen und nach jedem whisper.cpp-Update.
# Die Einstellungen folgen whisper.cpps eigenem Apple-Bauskript (build-xcframework.sh).

set -euo pipefail
cd "${0:A:h}/.."

source_dir=Vendor/whisper.cpp
build_dir=Vendor/whisper-build

cmake -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_METAL_USE_BF16=ON \
    -DGGML_BLAS_DEFAULT=ON \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF

cmake --build "$build_dir" --config Release -j "$(sysctl -n hw.ncpu)"

# Alle Teilbibliotheken an einen festen Ort, auf den das Xcode-Projekt zeigt.
mkdir -p "$build_dir/lib"
find "$build_dir" -name '*.a' -not -path "$build_dir/lib/*" -exec cp {} "$build_dir/lib/" \;
ls "$build_dir/lib"
