#
# CocoaPods cannot drive the OpenCV CMake build, so iOS and macOS consume a prebuilt xcframework.
# Produce it (into ./Frameworks) on a Mac with ../apple/build.sh before `flutter build macos`.
#
Pod::Spec.new do |s|
  s.name             = 'photokeeper_core'
  s.version          = '0.1.0'
  s.summary          = 'PhotoKeeper C++ core for dart:ffi.'
  s.description      = 'OpenCV-based keep/delete classifier, statically linked.'
  s.homepage         = 'https://github.com/aritroCoder/photokeeper-cli'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'PhotoKeeper' => 'noreply@photokeeper.dev' }
  s.source           = { :path => '.' }
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.vendored_frameworks = 'Frameworks/photokeeper_core.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
