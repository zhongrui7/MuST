
#
# Options
#

option(WITH_ACCELERATION "Enable CUDA" OFF)
option(WITH_OPENMP "Build with OpenMP" ON)
option(WITH_LIBXC "Build with Libxc" ON)


include(CheckLanguage)

if (WITH_ACCELERATION)
    message(STATUS "CUDA is activated: " ${WITH_ACCELERATION})
    check_language(CUDA)
    if (CMAKE_CUDA_COMPILER)
        enable_language(CUDA)
    else ()
        message(STATUS "No CUDA compiler found")
    endif ()
else ()
    message(STATUS "CUDA is deactivated: " ${WITH_ACCELERATION})
endif ()

list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/cmake)

# Defining mst_main
add_executable(mst_main)

set_target_properties(mst_main PROPERTIES OUTPUT_NAME "MST")

set_target_properties(mst_main PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
        )


# Defining mst_lib
add_library(mst_lib)

set_target_properties(mst_lib PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
        ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
        Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/modules)

target_include_directories(mst_lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(mst_main PUBLIC mst_lib)

# Adding Subdirectories
add_subdirectory(src)
add_subdirectory(lib)
add_subdirectory(plib)
add_subdirectory(iolib)

#
# Compiler flags
#

if (CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")

    target_link_libraries(mst_lib PUBLIC "gcc")
    target_link_libraries(mst_lib PUBLIC "gfortran")

    target_compile_options(mst_lib PUBLIC "-ffree-line-length-none")

    if (CMAKE_Fortran_COMPILER_VERSION VERSION_GREATER_EQUAL "10.0.0")
        # Needed for gcc 10
        target_compile_options(mst_lib PUBLIC "-fallow-argument-mismatch")
    endif ()

endif ()


target_compile_definitions(mst_lib PUBLIC "Underscore")


# Find MPI Library
find_package(MPI REQUIRED COMPONENTS Fortran OPTIONAL_COMPONENTS)
target_link_libraries(mst_lib PUBLIC MPI::MPI_Fortran)
target_compile_definitions(mst_lib PUBLIC MPI)

# Find OpenMP library
if (WITH_OPENMP)
    find_package(OpenMP REQUIRED)
    target_link_libraries(mst_lib PUBLIC OpenMP::OpenMP_Fortran)
endif ()


# Find XDR
find_package(XDR REQUIRED)

target_include_directories(mst_lib PUBLIC ${XDR_INCLUDE})
target_include_directories(mst_lib PUBLIC ${RPC_INCLUDE_DIR})

message(STATUS "XDR: " ${XDR_INCLUDE})
message(STATUS "XDR: " ${RPC_INCLUDE_DIR})

# Find FFTW
find_package(FFTW REQUIRED)

target_link_libraries(mst_lib PUBLIC ${FFTW_LIB})
target_link_libraries(mst_lib PUBLIC ${FFTW_LIBRARIES})
target_include_directories(mst_lib PUBLIC ${FFTW_INCLUDES})


#
# External libraries
#

# LIBXC
if (WITH_LIBXC)
    find_package(libxc REQUIRED)
    target_link_libraries(mst_lib PUBLIC libxc::libxc)
endif ()

# CUDA
if (WITH_ACCELERATION)

    target_compile_definitions(mst_lib PUBLIC ACCELERATOR_CUDA_C)

    option(CUDA_DEBUG "Debug CUDA routines" OFF)

    if (CUDA_DEBUG)
        target_compile_definitions(mst_lib PUBLIC "CUDA_DEBUG")
    endif ()


    # Build with OpenMP
    if (WITH_OPENMP)
        message(STATUS "OpenMP is also defined for GPU")
        target_compile_options(mst_lib PUBLIC $<$<COMPILE_LANGUAGE:CUDA>:-Xcompiler -fopenmp>)
    endif ()


    if (NOT DEFINED CMAKE_CUDA_STANDARD)
        set(CMAKE_CUDA_STANDARD 14)
        set(CMAKE_CUDA_STANDARD_REQUIRED ON)
    endif ()

    if (NOT DEFINED CMAKE_CUDA_SEPARABLE_COMPILATION)
        set(CMAKE_CUDA_SEPARABLE_COMPILATION OFF)
    endif ()

    find_package(CUDAToolkit REQUIRED)


    message(STATUS "CUDA Version: " ${CUDAToolkit_VERSION})
    message(STATUS "CUDA Include dirs: " ${CUDAToolkit_INCLUDE_DIRS})
    message(STATUS "CUDA Library: " ${CUDAToolkit_LIBRARY_DIR})

    target_link_libraries(mst_lib PUBLIC CUDA::toolkit)

    # Check if the necessary libraries have been found
    if (TARGET CUDA::cublas)
        target_link_libraries(mst_lib PUBLIC CUDA::cublas)
    else ()
        message(FATAL_ERROR "CuBLAS was not defined or found")
    endif ()

    if (TARGET CUDA::cusolver)
        target_link_libraries(mst_lib PUBLIC CUDA::cusolver)
    else ()
        message(FATAL_ERROR "Cusolver was not defined or found")
    endif ()
endif ()


# Find HDF5
message(STATUS "Find HDF5")
set(HDF5_PREFER_PARALLEL false)
find_package(HDF5 REQUIRED COMPONENTS Fortran C)

message(STATUS "HDF5 C Libaries: " "${HDF5_C_LIBRARIES}")
message(STATUS "HDF5 LIBRARIES: " "${HDF5_LIBRARIES}")
message(STATUS "HDF5 INCLUDE DIRS: " "${HDF5_INCLUDE_DIRS}")
message(STATUS "HDF5 Version: " "${HDF5_VERSION}")

target_link_libraries(mst_lib PUBLIC HDF5::HDF5)

# Linear algebra libraries
option(USE_ESSL "Use IBM ESSL library" OFF)

if (USE_ESSL)
    find_package(ESSL REQUIRED)
    set(ESSL_WORKAROUND True)

    target_link_libraries(mst_lib PUBLIC ESSL)
else ()
    # Lapack
    option(SEARCH_LAPACK "Search for LAPACK" ON)
    if (NOT SEARCH_LAPACK)
        add_library(LAPACK::LAPACK STATIC IMPORTED GLOBAL)
        set_target_properties(LAPACK::LAPACK PROPERTIES IMPORTED_LOCATION ${LAPACK_LIBRARIES})
        if (DEFINED LAPACK_LINKER_FLAGS)
            target_compile_options(LAPACK::LAPACK INTERFACE ${LAPACK_LINKER_FLAGS})
        endif ()
        if (DEFINED LAPACK_INCLUDE_DIR)
            target_include_directories(LAPACK::LAPACK INTERFACE ${LAPACK_INCLUDE_DIR})
        endif ()
    else ()
        if (NOT DEFINED BLA_VENDOR)
            set(BLA_VENDOR "Generic")
        endif ()
        find_package(LAPACK REQUIRED)
    endif ()
    target_link_libraries(mst_lib PUBLIC LAPACK::LAPACK)


    # BLAS
    option(SEARCH_BLAS "Search for BLAS" ON)
    if (NOT SEARCH_BLAS)
        add_library(BLAS::BLAS STATIC IMPORTED GLOBAL)
        set_target_properties(BLAS::BLAS PROPERTIES IMPORTED_LOCATION ${BLAS_LIBRARIES})
        if (DEFINED BLAS_LINKER_FLAGS)
            target_compile_options(BLAS::BLAS INTERFACE ${BLAS_LINKER_FLAGS})
        endif ()
        if (DEFINED BLAS_INCLUDE_DIR)
            target_include_directories(BLAS::BLAS INTERFACE ${BLAS_INCLUDE_DIR})
        endif ()

    else ()
        if (NOT DEFINED BLA_VENDOR)
            set(BLA_VENDOR "Generic")
        endif ()
        find_package(BLAS REQUIRED)
    endif ()
    target_link_libraries(mst_lib PUBLIC BLAS::BLAS)
endif ()
