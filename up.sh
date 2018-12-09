#!/bin/bash

./install-core.sh | tee install-core-full-log.log

./install-optional.sh | tee install-core-full-log.log
