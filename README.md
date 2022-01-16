# SolidRun's i.MX8MM based HummingBoard Pulse build scripts

## Introduction
Main intention of this repository is to a buildroot based build environment for i.MX8MM based product evaluation.

The build script provides ready to use images that can be deployed on micro SD and future on eMMC.

## Build with host tools
Simply running ./runme.sh, it will check for required tools, clone and build images and place results in images/ directory.

## Deploying
For SD card bootable images, plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/microsd-<hash>.img of=/dev/sdX`

And then set the HummingBoard Pulse DIP switch to boot from SD
