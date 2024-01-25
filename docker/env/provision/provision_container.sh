#!/bin/sh

home="/home/user"

# Set up alire:
echo "Setting up Alire build dependencies."
export PATH=$PATH:$home/env/bin
cd $home/share/adamant
alr -n build --release
alr -n toolchain --select gnat_native
alr -n toolchain --select gprbuild
cd $home/share/adamant_example
alr -n build --release
echo "Done."
