#!/usr/bin/env python

import os
import configparser
import sys

if len(sys.argv) == 1:
    print('=== this script requires one argument, usage: set-aws-profile.py target-profile')
    sys.exit(1)

profile = sys.argv[1]

credentials_file_path = f'{os.path.expanduser("~")}/.aws/credentials'
if not os.path.exists(credentials_file_path):
    print(f'=== AWS credentials file at {credentials_file_path} not found')
    sys.exit(1)

config = configparser.ConfigParser()
config.read(credentials_file_path)

if not profile in config:
    print(f'=== profile [{profile}] not found in credentials file')
    sys.exit(1)

if not 'default' in config:
    print('=== profile [default] not found in credentials file, creating one')
    config['default'] = {}

print(f'=== setting AWS profile [{sys.argv[1]}] as default profile')
config['default']['aws_access_key_id'] = config[profile]['aws_access_key_id']
config['default']['aws_secret_access_key'] = config[profile]['aws_secret_access_key']

with open(credentials_file_path, 'w') as credentials_file:
    config.write(credentials_file)
