#!/usr/bin/env python

from utilities import read_credentials_file, read_config_file

def get_credentials_profiles():
    credentials_file = read_credentials_file()
    return [section_name for section_name in credentials_file.sections() if section_name != 'default']

def get_config_profiles_with_assumed_role():
    config_file = read_config_file()
    return [section_name for section_name in config_file.sections()
                if section_name != 'default' and
                    config_file.has_option(section_name, 'role_arn') and
                    config_file.has_option(section_name, 'source_profile')]

print("\n".join(get_credentials_profiles() + get_config_profiles_with_assumed_role()))
