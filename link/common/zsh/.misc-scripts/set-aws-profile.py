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

config_file_path = f'{os.path.expanduser("~")}/.aws/config'
if not os.path.exists(config_file_path):
    print(f'=== AWS config file at {config_file_path} not found')
    sys.exit(1)

credentials_config = configparser.ConfigParser()
credentials_config.read(credentials_file_path)

config = configparser.ConfigParser()
config.read(config_file_path)

profile_is_in_credentials_file = profile in credentials_config
profile_is_in_config_file = profile in config

if (not profile_is_in_credentials_file) and (not profile_is_in_config_file):
    print(f'=== profile [{profile}] not found in either credentials or config file')
    sys.exit(1)

if not 'default' in credentials_config:
    print('=== profile [default] not found in credentials file, creating one')
    credentials_config['default'] = {}

if not 'default' in config:
    print('=== profile [default] not found in config file, creating one')
    config['default'] = {}

if profile_is_in_credentials_file:
    print(f'=== setting AWS profile [{profile}] as default profile')
    credentials_config['default']['aws_access_key_id'] = credentials_config[profile]['aws_access_key_id']
    credentials_config['default']['aws_secret_access_key'] = credentials_config[profile]['aws_secret_access_key']
    config['default'].pop('role_arn', None)
    config['default'].pop('source_profile', None)

if profile_is_in_config_file:
    print(f'=== assuming AWS profile [{profile}]')
    config['default']['role_arn'] = config[profile]['role_arn']
    config['default']['source_profile'] = config[profile]['source_profile']

with open(credentials_file_path, 'w') as credentials_file:
    credentials_config.write(credentials_file)

with open(config_file_path, 'w') as config_file:
    config.write(config_file)
