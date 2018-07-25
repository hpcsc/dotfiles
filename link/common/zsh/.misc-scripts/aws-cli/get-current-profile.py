#!/usr/bin/env python

import sys
from utilities import read_credentials_file, read_config_file

config_file = read_config_file()
if ('default' in config_file and
    config_file.has_option('default', 'role_arn') and
    config_file.has_option('default', 'source_profile')):

    default_role_arn = config_file.get('default', 'role_arn')
    default_source_profile = config_file.get('default', 'source_profile')

    for section in config_file.sections() or []:
        if (section != 'default' and
            config_file.has_option(section, 'role_arn') and
            config_file.has_option(section, 'source_profile') and
            config_file[section]['role_arn'] == default_role_arn and
            config_file[section]['source_profile'] == default_source_profile):
            print(section)
            sys.exit(0)

credentials_file = read_credentials_file()
if ('default' in credentials_file and
    credentials_file.has_option('default', 'aws_access_key_id')):
    default_aws_access_key_id = credentials_file.get('default', 'aws_access_key_id')
    for section in credentials_file.sections() or []:
        if (section != 'default' and
            credentials_file.has_option(section, 'aws_access_key_id') and
            credentials_file[section]['aws_access_key_id'] == default_aws_access_key_id):
            print(section)
            sys.exit(0)
