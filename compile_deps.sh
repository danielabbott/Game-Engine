set -e

cd deps/glfw
#sudo apt-get install build-essential	
#sudo apt-get install xorg-dev
# GLFW has been modified - all the vulkan code has been removed to fix link issues on linux when no vulkan implementation is present.
cmake -DBUILD_SHARED_LIBS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF .
make -j3

cd ../glad
gcc -c glad.c -o glad.o -I.

cd ../stb_image
gcc -c stb_image.c -o stb_image.o -I. -msse2

cd ../zstd/lib
make -j3

echo Dependencies Built.
