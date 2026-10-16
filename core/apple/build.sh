#!/bin/sh
# Build photokeeper_core.xcframework (iOS device + simulator, macOS arm64) for the podspecs to vendor.
# UNTESTED: written on Linux; needs a Mac with Xcode and CMake >= 3.24. Takes several minutes per slice (OpenCV from source).
set -eu
cd "$(dirname "$0")"
rm -rf out && mkdir -p out
slice() {  # name, cmake args...
  name=$1; shift
  # CPU_DISPATCH empty: the Xcode generator drops OpenCV's dispatched NEON objects, so the dnn
  # kernels they reference never get linked. Compiling NEON as the baseline avoids that.
  cmake -S ../src -B "out/$name" -G Xcode -DCMAKE_BUILD_TYPE=Release -DCPU_BASELINE=NEON -DCPU_DISPATCH= "$@"
  cmake --build "out/$name" --config Release --target photokeeper_core
}
slice ios        -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
slice iossim     -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
slice macos      -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15
xcodebuild -create-xcframework \
  -framework out/ios/Release-iphoneos/photokeeper_core.framework \
  -framework out/iossim/Release-iphonesimulator/photokeeper_core.framework \
  -framework out/macos/Release/photokeeper_core.framework \
  -output out/photokeeper_core.xcframework
# podspecs cannot reference files outside their own directory, so each gets a copy
for p in ios macos; do
  rm -rf "../$p/Frameworks" && mkdir -p "../$p/Frameworks" && cp -R out/photokeeper_core.xcframework "../$p/Frameworks/"
done
