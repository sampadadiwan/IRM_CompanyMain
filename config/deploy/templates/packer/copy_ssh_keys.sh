#!/bin/bash

# Create .ssh directory if it doesn't exist and set permissions
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
chown ubuntu:ubuntu /home/ubuntu/.ssh