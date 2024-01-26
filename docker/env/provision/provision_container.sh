#!/bin/sh

home="/home/user"

# Git config fix:
git config --global --add safe.directory /home/user/adamant
git config --global --add safe.directory /home/user/adamant_example

# Set up alire:
echo "Setting up Alire build dependencies."
export PATH=$PATH:$home/env/bin
cd $home/adamant
alr -n build --release
alr -n toolchain --select gnat_native
alr -n toolchain --select gprbuild
cd $home/adamant_example
alr -n build --release
echo "Done."
