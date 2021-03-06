## OpenGL forward renderer.

Tested with Zig 0.6.0

Demo 1:
![Demo 1 Screenshot](https://raw.githubusercontent.com/danielabbott/Game-Engine/master/docs/screenshot.jpg)
(Credit for farm assets is in the DemoAssets directory)

### Modules

* WindowGraphicsInput: Abstraction over window creation (GLFW 3), user input (GLFW 3), and the graphics API (OpenGL 3.3, GLAD).<br>Depends on: GLFW, GLAD, stb_image, RefCount.zig, Files.zig

* Mathematics: Matrix and Vector types

* ModelFiles: Loading of models and animations from the custom file formats

* RTRenderEngine: Real-time rendering of scenes.<br>Depends on: WindowGraphicsInput, Mathematics, ModelFiles, Assets, Files.zig, RefCount.zig

* Compress: Custom compressed file format.<br>Depends on: ZSTD, Files.zig

* Assets: Abstraction ovet the loading of assets such as models, animations, textures, etc.<br>Depends on: Compress, ConditionVariable.zig, Files.zig ModelFiles, RefCount.zig

* Scene: Scene files.<br>Depends on: Assets, RTRenderEngine, Files.zig, Mathematics, WindowGraphicsInput
	
* RGB10A2: 10-bits-per-channel texture support.<br>Depends on: Files.zig


### Compile Instructions (Windows)

1. Run compile_deps.bat
	* Modify the file if needed e.g. to change the visual studio version
2. If compiling GLFW, open deps\glfw\GLFW.sln and build the GLFW project in Release x64. 
3. If compiling ZSTD, open deps\zstd\build\VS2010\zstd.sln and compile libzstd in Release x64.
4. Run compile_and_run.bat

Output is in zig-cache/bin. The batch script ^ will run the example program automatically.

### Compile Instructions (Linux, untested)

1. Run compile_deps.sh (might need to run sudo chmod +x ./compile_deps.sh)
	* Change 'make -j3' to 'make -j4' etc. wherever it appears in the script if your computer has more than 2 CPU cores.
2. Run 'zig build'

Output is in zig-cache/bin.

Demo programs must be run from the root directory of the project.

#### N.B.

A lot of structs have reference counting. If this isn't needed the functionality can be safely ignored by the calling code.
