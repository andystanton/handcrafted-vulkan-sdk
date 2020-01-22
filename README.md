# Handcrafted Vulkan SDK

A script that assembles something that looks like v1.2.131 of the [LunarG Vulkan SDK](http://lunarg.com/vulkan-sdk/) for macOS by checking out and building the individual components.

## Background

As part of macOS Catalina, Apple require binaries to be notarized. This meant that the executables and libraries included in the LunarG Vulkan SDK up to at least v1.1.130 [are not directly usable](https://vulkan.lunarg.com/issue/view/5d9b73d786da81451cc37e7b) in macOS Catalina.

There is a workaround: it's possible to right click on a non-notarized excutable or library and ⌥-click on Open. This presents you with a dialog that asks if you want to allow this file to be opened. You have to repeat this a few times for each of the libraries and executables you might want to use. For me this was the glslc executable, and the Vulkan loader, MoltenVK, Khronos validation layer and LunarG API dump validation layer libraries. Yes, you have to 'open' libraries to use this workaround.

As of v1.1.130, LunarG do not publicly provide the process by which they put together the SDK. This script aims to produce a similar output to the LunarG Vulkan SDK, partly to address the notarization issue, but also to allow custom builds of the SDK.

## What's in it?

The following repositories are built in this order:

* [KhronosGroup/SPIRV-Headers](https://github.com/KhronosGroup/SPIRV-Headers)
* [KhronosGroup/SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools)
* [KhronosGroup/SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)
* [KhronosGroup/glslang](https://github.com/KhronosGroup/glslang)
* [google/shaderc](https://github.com/google/shaderc)
* [KhronosGroup/Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers)
* [KhronosGroup/Vulkan-Loader](https://github.com/KhronosGroup/Vulkan-Loader)
* [KhronosGroup/Vulkan-ValidationLayers](https://github.com/KhronosGroup/Vulkan-ValidationLayers)
* [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK)
* [KhronosGroup/Vulkan-Tools](https://github.com/KhronosGroup/Vulkan-Tools)
* [LunarG/VulkanTools](https://github.com/LunarG/VulkanTools)

## Requirements

* CMake
* make
* Python 3
* Xcode

### Optional

* Qt5 for building vkconfig.app

## Build

```sh
git clone https://github.com/andystanton/handcrafted-vulkan-sdk.git
cd handcrafted-vulkan-sdk
./build-sdk.sh
```

This will create a directory called `vulkansdk-macos-1.2.131.handcrafted` containing the SDK. On a 2015 Macbook Pro with 4 cores and 16GB RAM this takes about 1 hour. A rebuild takes about a minute.

## Installation

I have intentionally not provided a way to install to system paths like `/usr/local` because this script is already juggling several chainsaws.

Instead you can move the built SDK to a known path and set environment variables as described in the [LunarG Vulkan SDK docs](https://vulkan.lunarg.com/doc/sdk/latest/mac/getting_started.html).

For example I move it to `$HOME/.vulkan/vulkansdk-macos-1.2.131.handcrafted` and create a symlink `$HOME/.vulkan/current` that points to it. My environment variables are then:

```sh
export VULKAN_SDK="$HOME/.vulkan/current/macOS"
export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:$VULKAN_SDK/lib"
export VK_ICD_FILENAMES="$VULKAN_SDK/etc/vulkan/icd.d/MoltenVK_icd.json"
export VK_LAYER_PATH="$VULKAN_SDK/etc/vulkan/explicit_layer.d"
export PATH="$PATH:$VULKAN_SDK/bin"
```

I have tested this with my personal CMake projects and they work as expected with the builtin `find_package(vulkan)`.

## Future

The future of this script is based around solving the following problems:

### This script exists

This script doesn't need to exist. For it to be obsolete:
1. Apple could endorse Vulkan and drop the notarization requirement for it, even if they don't support it. This is unlikely to happen.
2. LunarG could notarize the binaries in the SDK. They have said they will do this! But it would also be great if...
3. LunarG could make their SDK creation process open source. Being able to run custom builds of the SDK would be very cool!

### Each repository has its own way of managing its dependencies

The dependency management of these projects is varied. Most have similar-but-slightly-different approaches to version management. Some of the projects perform their own builds of other projects that are part of the SDK. This is exacerbated by C/C++ projects generally being awful to manage dependencies for.

I don't have a solution for this. It would be great if Khronos and LunarG could come up with a uniform way of doing this. I don't know if that would include doing something other than CMake based builds because C/C++ package managers terrify me.

### The script is only for macOS

My primary use case is to address the notarization issue introduced with macOS Catalina, but supporting custom SDK builds would be useful across all platforms. This script was put together by assembling the build instructions for each of its components for macOS, so extending it to support Linux and adding a Windows version is a case of doing the same for those platforms.

## License

This script is MIT licensed. The software it builds is subject to whatever licenses used by that software.

## Disclaimer

I do not work with low-level graphics APIs or C/C++ as a profession - I am only a hobbyist with graphics programming. Therefore do not trust what I say on the subject and please do the appropriate research yourself.
