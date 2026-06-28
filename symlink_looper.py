#!/usr/bin/env python3
import os as o
import shutil

userPath = "/home/" + o.environ["USER"] + "/"
dotFilePath = userPath + ".dots/"
o.makedirs(dotFilePath, exist_ok=True)

print("what is the directory to loop through? ")
directory = input()

targetDir = userPath + directory

print(f"Here is the contents of {directory}:\n{o.listdir(targetDir)}\n")


for name in o.listdir(targetDir):
    src = o.path.join(targetDir, name)
    dest = o.path.join(dotFilePath, name)

    if o.path.islink(src):
        print(f"{name} is already linked - moving on ...\n")
        continue

    if input(f"Would you like to symlink {name}? [y,N]") == "y":
        shutil.move(src, dest)
        print(f"\nMoving {name}")
        o.symlink(dest, src)
    else:
        print(f"skipped {name}, moving on ...")
