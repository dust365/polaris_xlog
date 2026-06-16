cmake_minimum_required (VERSION 3.6)

set(CMAKE_INSTALL_PREFIX "${CMAKE_BINARY_DIR}" CACHE PATH "Installation directory" FORCE)
message(STATUS "CMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}")

include_directories(openssl/include)

add_subdirectory(comm comm)
add_subdirectory(boot boot)
add_subdirectory(boost boost)
add_subdirectory(xlog xlog)

# zstd (xlog log compression)
option(ZSTD_BUILD_STATIC "BUILD STATIC LIBRARIES" ON)
option(ZSTD_BUILD_SHARED "BUILD SHARED LIBRARIES" OFF)
set(ZSTD_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/zstd")
set(LIBRARY_DIR ${ZSTD_SOURCE_DIR}/lib)
include(GNUInstallDirs)
add_subdirectory(zstd/build/cmake/lib zstd)

project (mars)

include(comm/utils.cmake)

include_directories(.)
include_directories(..)

set(SELF_LIBS_OUT ${CMAKE_SYSTEM_NAME}.out)

if(ANDROID)
    find_library(log-lib log)
    find_library(z-lib z)

    set(SELF_LIB_NAME marsxlog)
    file(GLOB SELF_SRC_FILES libraries/mars_android_sdk/jni/JNI_OnLoad.cc
            libraries/mars_xlog_sdk/jni/import.cc)
    add_library(${SELF_LIB_NAME} SHARED ${SELF_SRC_FILES})
    install(TARGETS ${SELF_LIB_NAME} LIBRARY DESTINATION ${SELF_LIBS_OUT} ARCHIVE DESTINATION ${SELF_LIBS_OUT})

    get_filename_component(EXPORT_XLOG_EXP_FILE libraries/mars_android_sdk/jni/export.exp ABSOLUTE)
    # --undefined-version: export.exp lists a few symbols absent in this build;
    # modern lld errors on that, so tolerate it (old GNU ld behaviour).
    set(SELF_XLOG_LINKER_FLAG "-Wl,--gc-sections -Wl,--version-script='${EXPORT_XLOG_EXP_FILE}' -Wl,--undefined-version")
    target_link_libraries(${SELF_LIB_NAME} "${SELF_XLOG_LINKER_FLAG}"
                            xlog mars-boost comm libzstd_static ${log-lib} ${z-lib})
endif()
