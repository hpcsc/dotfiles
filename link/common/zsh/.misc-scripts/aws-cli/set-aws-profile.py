#!/usr/bin/env python

import os
import sys
from utilities import read_credentials_file, read_config_file, credentials_file_path, config_file_path

def create_default_if_not_exists(config_file, config_file_name):
    if not 'default' in config_file:
        print(f'=== profile [default] not found in {config_file_name} file, creating one')
        config_file['default'] = {}

def write_config_to_file(config_file_path, config_file):
    with open(config_file_path, 'w') as opened_file:
        config_file.write(opened_file)

def is_assumed_role_profile(profile, config):
    if not profile in config:
        return False

    return config[profile]['role_arn'] and config[profile]['source_profile']

def set_profile(profile):
    credentials_file = read_credentials_file()
    config_file = read_config_file()

    create_default_if_not_exists(credentials_file, 'credentials')
    create_default_if_not_exists(config_file, 'config')

    if profile in credentials_file:
        print(f'=== setting AWS profile [{profile}] as default profile')
        credentials_file['default']['aws_access_key_id'] = credentials_file[profile]['aws_access_key_id']
        credentials_file['default']['aws_secret_access_key'] = credentials_file[profile]['aws_secret_access_key']
        config_file['default'].pop('role_arn', None)
        config_file['default'].pop('source_profile', None)
        write_config_to_file(credentials_file_path, credentials_file)
        write_config_to_file(config_file_path, config_file)
    elif is_assumed_role_profile(profile, config_file):
        print(f'=== assuming AWS profile [{profile}]')
        config_file['default']['role_arn'] = config_file[profile]['role_arn']
        config_file['default']['source_profile'] = config_file[profile]['source_profile']
        write_config_to_file(config_file_path, config_file)
    else:
        print(f'=== profile [{profile}] not found in either credentials or config file')
        sys.exit(1)

if len(sys.argv) == 1:
    print('=== this script requires one argument, usage: set-aws-profile.py target-profile')
    sys.exit(1)

profile = sys.argv[1]
set_profile(profile)
