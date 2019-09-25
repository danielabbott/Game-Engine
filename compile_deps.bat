cd deps/glfw && cmake -DBUILD_SHARED_LIBS=OFF -DGLFW_BUILD_EXAMPLES=OFF -DGLFW_BUILD_TESTS=OFF -DGLFW_BUILD_DOCS=OFF -DUSE_MSVC_RUNTIME_LIBRARY_DLL=OFF -G "Visual Studio 16 2019" . && cd ..\..
if %errorlevel% neq 0 exit /b %errorlevel%
echo ********** GLFW Visual Studio project files created. Load them in VS to compile GLFW (use RELEASE build mode). **********

echo ********** Load stb_image visual studio project and compile the Release x64 build. **********
echo ********** Load zstd visual studio project and compile the Release x64 build. **********

cd deps/glad && zig cc -c glad.c -o glad.o -I. && cd ..\..
if %errorlevel% neq 0 exit /b %errorlevel%


cd deps/stb_image && zig cc -c stb_image.c -o stb_image.o -I. -msse2 && cd ..\..

pause