# Builds libphotokeeper_core.{so,dll}: the C ABI from the CLI repo plus its static `pipeline` + OpenCV.
# Used directly by linux/, windows/ and android/ (Gradle); apple/build.sh drives it for iOS/macOS.
cmake_minimum_required(VERSION 3.24)  # the CLI repo needs it (FetchContent + PROJECT_IS_TOP_LEVEL)
project(photokeeper_core_library LANGUAGES C CXX)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)  # static OpenCV + pipeline end up inside a shared library

# The C++ core is its own repo. A sibling checkout wins so core changes can be developed in place;
# otherwise fetch it. shortcut: GIT_TAG main, pin a commit before the first release.
include(FetchContent)
set(sibling "${CMAKE_CURRENT_SOURCE_DIR}/../../../photokeeper")
if(EXISTS "${sibling}/CMakeLists.txt")
  set(FETCHCONTENT_SOURCE_DIR_PHOTOKEEPER "${sibling}")
endif()
FetchContent_Declare(photokeeper GIT_REPOSITORY https://github.com/aritroCoder/photokeeper-cli.git GIT_TAG main)
FetchContent_MakeAvailable(photokeeper)

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
