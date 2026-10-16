#!/bin/sh
# Build photokeeper_core.xcframework (iOS device + simulator, macOS arm64) for the podspecs to vendor.
# Needs a Mac with Xcode, Ninja and CMake >= 3.24. OpenCV from source takes several minutes per slice.
set -eu
cd "$(dirname "$0")"
rm -rf out && mkdir -p out
command -v ninja >/dev/null || brew install ninja
slice() {  # name, cmake args...
  name=$1; shift
  # Ninja, not the Xcode generator: with Xcode the NEON compile check runs before the iOS toolchain
  # is applied, reports NEON unavailable, and the dnn kernels are left out of the link.
  cmake -S ../src -B "out/$name" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCPU_BASELINE=NEON -DCPU_DISPATCH= "$@"
  cmake --build "out/$name" --target photokeeper_core
}
slice ios     -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
                 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
slice iossim  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphonesimulator \
                 -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
slice macos   -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15
xcodebuild -create-xcframework \
  -framework out/ios/photokeeper_core.framework \
  -framework out/iossim/photokeeper_core.framework \
  -framework out/macos/photokeeper_core.framework \
  -output out/photokeeper_core.xcframework
# podspecs cannot reference files outside their own directory, so each gets a copy
for p in ios macos; do
  rm -rf "../$p/Frameworks" && mkdir -p "../$p/Frameworks" && cp -R out/photokeeper_core.xcframework "../$p/Frameworks/"
done
