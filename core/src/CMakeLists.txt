# Builds libphotokeeper_core.{so,dll}: the C ABI from the CLI repo plus its static `pipeline` + OpenCV.
# Used directly by linux/, windows/ and android/ (Gradle); apple/build.sh drives it for iOS/macOS.
cmake_minimum_required(VERSION 3.24)  # the CLI repo needs it (FetchContent + PROJECT_IS_TOP_LEVEL)
project(photokeeper_core_library LANGUAGES C CXX)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)  # static OpenCV + pipeline end up inside a shared library

# The C++ core is its own repo. A sibling checkout wins so core changes can be developed in place;
# otherwise (CI) fetch this immutable revision. Bump it to pick up native changes;
# the Apple framework cache includes this file so a revision bump invalidates it.
include(FetchContent)
set(sibling "${CMAKE_CURRENT_SOURCE_DIR}/../../../photokeeper")
if(EXISTS "${sibling}/pipeline_c/pk.h")  # not just any ../photokeeper: in CI that is this app repo itself
  set(FETCHCONTENT_SOURCE_DIR_PHOTOKEEPER "${sibling}")
endif()
FetchContent_Declare(photokeeper
  GIT_REPOSITORY https://github.com/aritroCoder/photokeeper-cli.git
  GIT_TAG 9a24879f2d312e35408534e03aae0c96a0baeca6)
# OpenCV probes video backends even when videoio is outside BUILD_LIST. Its Orbbec SDK
# probe assumes OpenCV is the top-level project and fails when embedded on macOS arm64.
set(WITH_OBSENSOR OFF CACHE BOOL "Build without the unused Orbbec camera backend" FORCE)
# OpenCV resolves paths against the install prefix while configuring. Flutter's Windows runner caches that
# prefix as a generator expression, so every re-configure failed in OpenCV; nothing installs from here anyway.
set(CMAKE_INSTALL_PREFIX "${CMAKE_CURRENT_BINARY_DIR}/unused-install")
FetchContent_MakeAvailable(photokeeper)
# Flutter bundles photokeeper_core below; the static dependencies need no installation.
# Exclude the entire dependency tree so INSTALL cannot enter OpenCV, whose install
# script is disabled by the core repo. Linked targets still build as dependencies.
set_property(DIRECTORY "${photokeeper_SOURCE_DIR}" PROPERTY EXCLUDE_FROM_ALL TRUE)

add_library(photokeeper_core SHARED "${photokeeper_SOURCE_DIR}/pipeline_c/pk.cpp")
target_link_libraries(photokeeper_core PRIVATE pipeline)
set_target_properties(photokeeper_core PROPERTIES
  OUTPUT_NAME "photokeeper_core"
  CXX_VISIBILITY_PRESET hidden  # only PK_API symbols leave the library
  PUBLIC_HEADER "${photokeeper_SOURCE_DIR}/pipeline_c/pk.h")

if(ANDROID)
  target_link_options(photokeeper_core PRIVATE "-Wl,-z,max-page-size=16384")  # Android 15 16k pages
endif()
if(APPLE)
  set_target_properties(photokeeper_core PROPERTIES
    FRAMEWORK TRUE
    MACOSX_FRAMEWORK_IDENTIFIER dev.photokeeper.core
    MACOSX_FRAMEWORK_BUNDLE_VERSION 1
    MACOSX_FRAMEWORK_SHORT_VERSION_STRING 1.0)
endif()
