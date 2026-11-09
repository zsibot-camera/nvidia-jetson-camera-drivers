#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "depth_sdk::depth_sdk" for configuration "Release"
set_property(TARGET depth_sdk::depth_sdk APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(depth_sdk::depth_sdk PROPERTIES
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libdepth_sdk.so"
  IMPORTED_SONAME_RELEASE "libdepth_sdk.so"
  )

list(APPEND _cmake_import_check_targets depth_sdk::depth_sdk )
list(APPEND _cmake_import_check_files_for_depth_sdk::depth_sdk "${_IMPORT_PREFIX}/lib/libdepth_sdk.so" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
