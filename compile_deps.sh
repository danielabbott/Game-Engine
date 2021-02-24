set -e

cd deps/glfw
#sudo apt-get install build-essential	
#sudo apt-get install xorg-dev
# GLFW has been modified - all the vulkan code has been removed to fix link issues on linux when no vulkan implementation is present.
cmake -DBUILD_SHARED_LIBS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF .
make -j3

cd ../zstd/lib
make -j3

echo Dependencies Built.
