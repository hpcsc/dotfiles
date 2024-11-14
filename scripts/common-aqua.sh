#!/bin/bash

set -e

echo_yellow "=== Installing aqua"

rm -f /tmp/aqua-installer
curl -sSfL https://raw.githubusercontent.com/aquaproj/aqua-installer/v3.0.1/aqua-installer -o /tmp/aqua-installer
echo "fb4b3b7d026e5aba1fc478c268e8fbd653e01404c8a8c6284fdba88ae62eda6a  /tmp/aqua-installer" | sha256sum -c
chmod +x /tmp/aqua-installer
/tmp/aqua-installer
