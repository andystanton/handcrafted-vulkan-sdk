#!/usr/bin/env bash

set -e

# =============================================================================
# build constants
# =============================================================================

pushd $(dirname ${0}) >/dev/null
script_name=$(basename ${0})
script_path=$(pwd -P)
popd >/dev/null

sdk_version=1.2.131

source_path=${script_path}/source
build_path=${script_path}/build
base_output_path=${script_path}/vulkansdk-macos-${sdk_version}.handcrafted
output_path=${base_output_path}/macOS

repos=(
    KhronosGroup:SPIRV-Headers:1.5.1
    KhronosGroup:SPIRV-Tools:v2019.5
    KhronosGroup:SPIRV-Cross:2020-01-16
    KhronosGroup:glslang:4fc7a33910fb8e40b970d160e1b38ab3f67fe0f3
    google:shaderc:0f16fd2f0b94bdc174e795913b579b1433932118
    KhronosGroup:Vulkan-Headers:v${sdk_version}
    KhronosGroup:Vulkan-Loader:v${sdk_version}
    KhronosGroup:Vulkan-ValidationLayers:v${sdk_version}
    KhronosGroup:MoltenVK:v1.0.40
    KhronosGroup:Vulkan-Tools:v${sdk_version}
    LunarG:VulkanTools:sdk-1.2.130
)

# =============================================================================
# build utility functions
# =============================================================================

function get_revision() {
    target_org=$1
    target_repo=$2
    repo_regex='^(.+):(.+):(.+)$'

    for repo in ${repos[@]}; do
        gh_org=$(sed -E 's/'${repo_regex}'/\1/' <<<$repo)
        gh_repo=$(sed -E 's/'${repo_regex}'/\2/' <<<$repo)
        gh_version=$(sed -E 's/'${repo_regex}'/\3/' <<<$repo)
        if [[ ${gh_org} == ${target_org} ]] && [[ ${gh_repo} == ${target_repo} ]]; then
            echo ${gh_version}
            return
        fi
    done
    echo "unknown repository"
}

function get_source() {
    gh_org=$1
    gh_repo=$2
    gh_version=$(get_revision ${gh_org} ${gh_repo})
    gh_path=${source_path}/${gh_repo}

    echo "Fetching ${gh_org}/${gh_repo}:${gh_version}"

    if [ ! -d ${gh_path} ]; then
        git clone "https://github.com/${gh_org}/${gh_repo}.git" ${gh_path} &>/dev/null
    fi

    pushd ${gh_path} >/dev/null

    git fetch --all >/dev/null
    git -c advice.detachedHead=false checkout ${gh_version} &>/dev/null
    git pull origin ${gh_version} &>/dev/null

    popd >/dev/null
}

function cmake_build() {
    project_repo=${1}; shift
    project_generator=${1}; shift
    project_name=$(sed -E 's/^([^\/]+)\/.*$/\1/' <<<$project_repo)
    project_source_path=${source_path}/${project_repo}
    project_build_path=${build_path}/${project_name}

    cmake_generator='Unknown'
    extra_build_args=()
    case $project_generator in
    make)
        cmake_generator='Unix Makefiles' 
        extra_build_args=(-- --quiet)
        ;;
    ninja)
        cmake_generator='Ninja' 
        ;;
    esac

    echo "Executing cmake build for ${project_name}"

    mkdir -p ${project_build_path}
    pushd ${project_build_path} >/dev/null

    cmake \
        "-G${cmake_generator}" \
        -Wno-dev \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=${output_path} \
        "${@}" \
        ${project_source_path}

    cmake \
        --build . \
        --target install \
        --parallel $(sysctl -n hw.activecpu) \
        "${extra_build_args[@]}"

    popd >/dev/null
}

function xcode_build() {
    project_repo=${1}; shift
    project_xcode_proj=${1}; shift
    project_scheme=${1}; shift
    project_name=$(sed -E 's/^([^\/]+)\/.*$/\1/' <<<$project_repo)
    project_source_path=${source_path}/${project_repo}
    project_build_path=${build_path}/${project_name}

    echo "Executing xcode build for ${project_name}"

    mkdir -p ${project_build_path}
    pushd ${project_build_path} >/dev/null

    xcodebuild \
        -quiet \
        -project "${project_xcode_proj}" \
        -scheme "${project_scheme}" \
        "${@}" \
        build

    popd >/dev/null
}

function fix_library_path() {
    source_file=$1
    target_file=$2
    search_regex='(\"library_path\":[[:space:]]*\")\.\/(lib[[:alnum:]_]+\.dylib)(\")'
    replace_regex='\1..\/..\/..\/lib\/\2\3'
    sed -E "s/${search_regex}/${replace_regex}/" ${source_file} >${target_file}
}

# =============================================================================
# per-project build functions
# =============================================================================

function build_spirv_headers() {
    get_source KhronosGroup SPIRV-Headers
    cmake_build SPIRV-Headers make
    cp ${output_path}/include/spirv/unified1/spirv.h ${output_path}/include/vulkan/spirv.h
}

function build_spirv_tools() {
    get_source KhronosGroup SPIRV-Tools

    pushd ${source_path}/SPIRV-Tools >/dev/null
    python3 ./utils/git-sync-deps >/dev/null
    popd >/dev/null
    
    cmake_build SPIRV-Tools make \
        -DSPIRV_SKIP_TESTS=on
}

function build_spirv_cross() {
    get_source KhronosGroup SPIRV-Cross
    cmake_build SPIRV-Cross make \
        -DSPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS=on \
        -DSPIRV_CROSS_ENABLE_TESTS=off \
        -DSPIRV_CROSS_STATIC=on \
        -DSPIRV_CROSS_SHARED=on \
        -DSPIRV_CROSS_CLI=on
}

function build_glslang() {
    get_source KhronosGroup glslang

    pushd ${source_path}/glslang >/dev/null
    ./update_glslang_sources.py >/dev/null 
    popd >/dev/null

    cmake_build glslang make \
        -DENABLE_OPT=off
}

function build_shaderc() {
    get_source google shaderc

    pushd ${source_path}/shaderc >/dev/null
    ./update_shaderc_sources.py >/dev/null
    popd >/dev/null

    cmake_build shaderc/src ninja \
        -DSKIP_GLSLANG_INSTALL=on \
        -DSKIP_SPIRV_TOOLS_INSTALL=on \
        -DSHADERC_ENABLE_INSTALL=on \
        -DINSTALL_GTEST=off
}

function build_vulkan_headers() {
    get_source KhronosGroup Vulkan-Headers
    cmake_build Vulkan-Headers make
}

function build_vulkan_loader() {
    get_source KhronosGroup Vulkan-Loader
    cmake_build Vulkan-Loader make \
        -DVULKAN_HEADERS_INSTALL_DIR=${output_path}

    rm -rf ${output_path}/Frameworks
    mv ${output_path}/loader ${output_path}/Frameworks
}

function build_vulkan_validation_layers() {
    get_source KhronosGroup Vulkan-ValidationLayers

    pushd ${source_path}/Vulkan-ValidationLayers >/dev/null
    ./scripts/update_deps.py --config release >/dev/null
    popd >/dev/null

    cmake_build Vulkan-ValidationLayers make \
        -DVULKAN_HEADERS_INSTALL_DIR=${output_path} \
        -DGLSLANG_INSTALL_DIR=${output_path} \
        -DCMAKE_INSTALL_RPATH:PATH=${output_path}/lib \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH:BOOL=TRUE \
        -C ${source_path}/${gh_repo}/helper.cmake \

    mkdir -p ${output_path}/etc/vulkan/explicit_layer.d
    fix_library_path \
        ${build_path}/Vulkan-ValidationLayers/layers/VkLayer_khronos_validation.json \
        ${output_path}/etc/vulkan/explicit_layer.d/VkLayer_khronos_validation.json

    mkdir -p ${output_path}/lib
    cp ${build_path}/Vulkan-ValidationLayers/layers/libVkLayer_khronos_validation.dylib ${output_path}/lib
}

function build_molten_vk() {
    get_source KhronosGroup MoltenVK

    pushd ${source_path}/MoltenVK >/dev/null
    ./fetchDependencies \
        --spirv-cross-root ${source_path}/SPIRV-Cross \
        --v-headers-root ${source_path}/Vulkan-Headers \
        >/dev/null
    popd >/dev/null

    mkdir -p ${build_path}/MoltenVK

    # The trailing `|| :` is a hack because the script uses `set -e` so is needed to prevent 
    #  the script from exiting when the `cp` command fails after the initial run because 
    #  of existing symlinks.
    cp -RH ${source_path}/${gh_repo}/ ${build_path}/MoltenVK/ 2>/dev/null || :

    xcode_build MoltenVK MoltenVKPackaging.xcodeproj "MoltenVK Package" \
        GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS MVK_LOGGING_ENABLED=0'

    rm -rf ${base_output_path}/MoltenVK
    cp -RH ${build_path}/MoltenVK/Package/Release/MoltenVK ${base_output_path} 2>/dev/null || :
    cp ${build_path}/MoltenVK/Package/Latest/MoltenVK/macOS/dynamic/libMoltenVK.dylib ${output_path}/lib 2>/dev/null || :

    mkdir -p ${output_path}/etc/vulkan/icd.d
    fix_library_path \
        ${build_path}/MoltenVK/MoltenVK/icd/MoltenVK_icd.json \
        ${output_path}/etc/vulkan/icd.d/MoltenVK_icd.json
}

function build_khronos_vulkan_tools() {
    get_source KhronosGroup Vulkan-Tools

    cmake_build Vulkan-Tools make \
        -DVULKAN_HEADERS_INSTALL_DIR=${output_path} \
        -DVULKAN_LOADER_INSTALL_DIR=${output_path} \
        -DMOLTENVK_REPO_ROOT=${build_path}/MoltenVK

    rm -rf ${base_output_path}/Applications/vkcube.app \
        ${base_output_path}/Applications/vkcubepp.app \
        ${base_output_path}/Applications/vulkaninfo.app

    mkdir -p ${base_output_path}/Applications
    mv ${output_path}/cube/vkcube.app \
        ${output_path}/cube/vkcubepp.app \
        ${output_path}/vulkaninfo/vulkaninfo.app \
        ${base_output_path}/Applications

    rm -rf ${output_path}/cube \
        ${output_path}/vulkaninfo
}

function build_lunarg_vulkan_tools() {
    get_source LunarG VulkanTools

    pushd ${source_path}/VulkanTools >/dev/null
    ./update_external_sources.sh >/dev/null 
    popd >/dev/null

    pushd ${source_path}/VulkanTools >/dev/null
    ./scripts/update_deps.py >/dev/null
    popd >/dev/null

    export CMAKE_PREFIX_PATH='/usr/local/opt/qt:$CMAKE_PREFIX_PATH'
    cmake_build VulkanTools make \
        -DVULKAN_HEADERS_INSTALL_DIR=${output_path} \
        -DVULKAN_LOADER_INSTALL_DIR=${output_path} \
        -DVULKAN_VALIDATIONLAYERS_INSTALL_DIR=${output_path} \
        -C ${source_path}/VulkanTools/helper.cmake

    mkdir -p ${output_path}/etc/vulkan/explicit_layer.d
    fix_library_path \
        ${build_path}/${gh_repo}/layersvt/VkLayer_api_dump.json \
        ${output_path}/etc/vulkan/explicit_layer.d/VkLayer_api_dump.json

    rm -rf ${base_output_path}/Applications/vkconfig.app
    if [ -d ${output_path}/bin/vkconfig.app ]; then
        mv ${output_path}/bin/vkconfig.app ${base_output_path}/Applications
    fi
}

# =============================================================================
# build process
# =============================================================================

mkdir -p ${source_path} ${build_path} ${output_path}

build_spirv_headers
build_spirv_tools
build_spirv_cross
build_glslang
build_shaderc
build_vulkan_headers
build_vulkan_loader
build_vulkan_validation_layers
build_molten_vk
build_khronos_vulkan_tools
build_lunarg_vulkan_tools
