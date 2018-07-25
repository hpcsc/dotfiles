import os
import configparser

credentials_file_path = f'{os.path.expanduser("~")}/.aws/credentials'
config_file_path = f'{os.path.expanduser("~")}/.aws/config'

def ensure_file_exists(file_path):
    if not os.path.exists(file_path):
        print(f'=== {file_path} not found')
        sys.exit(1)

def read_credentials_file():
    return read_config_file_with_path(credentials_file_path)

def read_config_file():
    return read_config_file_with_path(config_file_path)

def read_config_file_with_path(file_path):
    ensure_file_exists(file_path)
    config_file = configparser.ConfigParser()
    config_file.read(file_path)
    return config_file
