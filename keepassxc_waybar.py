import os
import subprocess as sp

print("opening db")
sp.run([
    "keepassxc-cli", "open",
    "--no-password",
    "--key-file", "/home/alt/sync/keepass/home_base",
    "/home/alt/sync/keepass/home_base.kdbx",
])
