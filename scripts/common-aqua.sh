#!/bin/bash

set -e

LATEST_INSTALLER_VERSION=$(curl -s https://api.github.com/repos/aquaproj/aqua-installer/releases/latest | jq -r '.tag_name')
echo_yellow "=== Installing aqua from installer ${LATEST_INSTALLER_VERSION}"

rm -f /tmp/aqua-installer
curl -sSfL https://raw.githubusercontent.com/aquaproj/aqua-installer/${LATEST_INSTALLER_VERSION}/aqua-installer -o /tmp/aqua-installer
chmod +x /tmp/aqua-installer
/tmp/aqua-installer
