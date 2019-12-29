#!/bin/bash

command -v ${HOME}/.krew/bin/kubectl-krew >/dev/null 2>&1 || {
    echo "=== ${HOME}/.krew/bin/kubectl-krew not available"
    exit 1
}

TARGET=./others/common/kube/krew-plugins
echo "=== Dumping krew plugins to ${TARGET}"
rm -f ${TARGET}
${HOME}/.krew/bin/kubectl-krew list > ${TARGET}
echo "=== Krew plugins dumped"

