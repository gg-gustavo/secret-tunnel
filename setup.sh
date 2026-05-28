#!/bin/bash

# Install tools
sudo apt update -y
sudo apt-get install -y \
    tcpreplay \
    tmux \
    python3-pip \
    tcpdump

sudo pip install -r requirements.txt

if [ -z "$PROJECT_SRC" ]; then
    echo export PROJECT_SRC=$(pwd) >> ~/.bashrc
fi

source ~/.bashrc
