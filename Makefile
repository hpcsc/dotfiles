dump-gnome-tweak-tool-config:
	dconf dump /org/gnome/desktop/input-sources/ > ./others/ubuntu/gnome-tweak-tool/keyboard.dconf

load-gnome-tweak-tool-config:
	dconf load /org/gnome/desktop/input-sources/ < ./others/ubuntu/gnome-tweak-tool/keyboard.dconf
