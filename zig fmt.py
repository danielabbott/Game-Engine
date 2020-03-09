import os
import subprocess

def format(dirName):
    files = os.listdir(dirName)
    for f in files:
        path = os.path.join(dirName, f)
        if os.path.isdir(path):
            format(path)
        else:
            ## FOR EACH FILE
            if path[-4:] == '.zig':
                # swap parameters for linux (untested)
                path = path[2:].replace('/', '\\')

                print(path)

                # uncomment to run zig fmt
                #subprocess.run(["zig", "fmt", path])

                

format('./')