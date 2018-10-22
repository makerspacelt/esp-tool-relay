#!/bin/bash

set -x


sudo apt-get update
sudo apt-get install -y --no-install-recommends make
sudo apt-get install -y python-pip

sudo pip install esptool
sudo pip install nodemcu-uploader


