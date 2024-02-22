#!/bin/bash

sudo apt --only-upgrade install google-chrome-stable

version=$(curl -s "https://chromedriver.storage.googleapis.com/LATEST_RELEASE")

wget -qP /tmp/ "https://chromedriver.storage.googleapis.com/${version}/chromedriver_linux64.zip"

sudo unzip -o /tmp/chromedriver_linux64.zip -d /usr/bin

sudo chmod 755 /usr/bin/chromedriver

echo "$version"
