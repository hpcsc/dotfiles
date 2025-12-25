dump-gnome-tweak-tool-config:
	dconf dump /org/gnome/desktop/input-sources/ > ./others/ubuntu/gnome-tweak-tool/keyboard.dconf

load-gnome-tweak-tool-config:
	dconf load /org/gnome/desktop/input-sources/ < ./others/ubuntu/gnome-tweak-tool/keyboard.dconf

setup-vscode:
	./others/ubuntu/vscode/setup.sh

dump-vscode-extensions:
	./others/common/vscode-backup-extensions.sh

install-aws-profile:
	curl -sL https://raw.githubusercontent.com/hpcsc/aws-profile/master/install | sudo bash
