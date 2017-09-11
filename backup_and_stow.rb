#!/usr/bin/env ruby
require 'fileutils'

# Usage: backup source_folder target_folder backup_folder
# iterate source_folder recursively, if found any file/folder with same name in target_folder,
# move that file/folder to backup_folder, keep structure of folder
def backup(source_folder, target_folder, backup_folder)
    FileUtils.mkdir_p backup_folder

    Dir.glob("#{source_folder}/.[!.]*").each do |f|
        base_name=File.basename(f)
        target=File.join(target_folder, base_name)
        if File.directory?(f) and File.directory?(target) and !File.symlink?(target)
            backup(f, target, File.join(backup_folder, base_name))
        elsif File.file?(target) or File.symlink?(target)
            puts "moving #{target} to #{backup_folder}"
            FileUtils.mv(target, backup_folder)
        end
    end
end

def backup_packages(packages, source_folder, target_folder, backup_folder)
    FileUtils.mkdir_p packages.map { |f| File.join(backup_folder, f) }

    packages.each do |f|
        backup(File.join(source_folder, f), target_folder, File.join(backup_folder, f))
    end
end

def stow_packages(packages)
    packages.each do |f|
        %x( stow "#{f}" )
    end
end

PACKAGES = ['git', 'vim', 'zsh', 'Applications']
backup_folder = File.expand_path('~/dotfiles_backup')
FileUtils.mkdir_p backup_folder
backup_packages(PACKAGES, File.expand_path('./'), File.expand_path('~'), backup_folder)
stow_packages(PACKAGES)
