#/bin/bash
# this script is modified from http://macapps.link/

clear && rm -rf ~/gui-temp && mkdir ~/gui-temp > /dev/null && cd ~/gui-temp

###############################
#    Define worker functions  #
###############################
versionChecker() {
	local v1=$1; local v2=$2;
	while [ `echo $v1 | egrep -c [^0123456789.]` -gt 0 ]; do
		char=`echo $v1 | sed 's/.*\([^0123456789.]\).*/\1/'`; char_dec=`echo -n "$char" | od -b | head -1 | awk {'print $2'}`; v1=`echo $v1 | sed "s/$char/.$char_dec/g"`; done
	while [ `echo $v2 | egrep -c [^0123456789.]` -gt 0 ]; do
		char=`echo $v2 | sed 's/.*\([^0123456789.]\).*/\1/'`; char_dec=`echo -n "$char" | od -b | head -1 | awk {'print $2'}`; v2=`echo $v2 | sed "s/$char/.$char_dec/g"`; done
	v1=`echo $v1 | sed 's/\.\./.0/g'`; v2=`echo $v2 | sed 's/\.\./.0/g'`;
	checkVersion "$v1" "$v2"
}

checkVersion() {
	[ "$1" == "$2" ] && return 1
	v1f=`echo $1 | cut -d "." -f -1`;v1b=`echo $1 | cut -d "." -f 2-`;v2f=`echo $2 | cut -d "." -f -1`;v2b=`echo $2 | cut -d "." -f 2-`;
	if [[ "$v1f" != "$1" ]] || [[ "$v2f" != "$2" ]]; then [[ "$v1f" -gt "$v2f" ]] && return 1; [[ "$v1f" -lt "$v2f" ]] && return 0;
		[[ "$v1f" == "$1" ]] || [[ -z "$v1b" ]] && v1b=0; [[ "$v2f" == "$2" ]] || [[ -z "$v2b" ]] && v2b=0; checkVersion "$v1b" "$v2b"; return $?
	else [ "$1" -gt "$2" ] && return 1 || return 0; fi
}

appStatus() {
  if [ ! -d "/Applications/$1" ]; then echo "uninstalled"; else
    if [[ $5 == "build" ]]; then BUNDLE="CFBundleVersion"; else BUNDLE="CFBundleShortVersionString"; fi
    INSTALLED=`/usr/libexec/plistbuddy -c Print:$BUNDLE: "/Applications/$1/Contents/Info.plist"`
      if [ $4 == "dmg" ]; then COMPARETO=`/usr/libexec/plistbuddy -c Print:$BUNDLE: "/Volumes/$2/$1/Contents/Info.plist"`;
      elif [[ $4 == "zip" || $4 == "tar" ]]; then COMPARETO=`/usr/libexec/plistbuddy -c Print:$BUNDLE: "$3$1/Contents/Info.plist"`; fi
    checkVersion "$INSTALLED" "$COMPARETO"; UPDATED=$?;
    if [[ $UPDATED == 1 ]]; then echo "updated"; else echo "outdated"; fi; fi
}
installApp() {
  app_extension=$1
  file_name=$2
  app_name=$3
  url=$4
  echo $'['$file_name'] Downloading app...'
  if [ $app_extension == "dmg" ]; then curl -s -L -o "$file_name.dmg" $url; yes | hdiutil mount -nobrowse "$file_name.dmg" -mountpoint "/Volumes/$file_name" > /dev/null;
    app_status=$(appStatus "$app_name" "$file_name" "" "dmg" "$7")
    if [[ $app_status == "updated" ]]; then echo $'['$file_name'] Skipped because it was already up to date!\n';
    elif [[ $app_status == "outdated" && $6 != "noupdate" ]]; then ditto "/Volumes/$file_name/$app_name" "/Applications/$app_name"; echo $'['$file_name'] Successfully updated!\n'
    elif [[ $app_status == "outdated" && $6 == "noupdate" ]]; then echo $'['$file_name'] This app cant be updated!\n'
    elif [[ $app_status == "uninstalled" ]]; then cp -R "/Volumes/$file_name/$app_name" /Applications; echo $'['$file_name'] Succesfully installed!\n'; fi
    hdiutil unmount "/Volumes/$file_name" > /dev/null && rm "$file_name.dmg"
  elif [ $app_extension == "zip" ]; then curl -s -L -o "$file_name.zip" $url; unzip -qq "$file_name.zip";
    app_status=$(appStatus "$app_name" "" "$5" "zip" "$7")
    if [[ $app_status == "updated" ]]; then echo $'['$file_name'] Skipped because it was already up to date!\n';
    elif [[ $app_status == "outdated" && $6 != "noupdate" ]]; then ditto "$5$app_name" "/Applications/$app_name"; echo $'['$file_name'] Successfully updated!\n'
    elif [[ $app_status == "outdated" && $6 == "noupdate" ]]; then echo $'['$file_name'] This app cant be updated!\n'
    elif [[ $app_status == "uninstalled" ]]; then mv "$5$app_name" /Applications; echo $'['$file_name'] Succesfully installed!\n'; fi;
    rm -rf "$file_name.zip" && rm -rf "$5" && rm -rf "$app_name"
  elif [ $app_extension == "tar" ]; then curl -s -L -o "$file_name.tar.bz2" $url; tar -zxf "$file_name.tar.bz2" > /dev/null;
    app_status=$(appStatus "$app_name" "" "$5" "tar" "$7")
    if [[ $app_status == "updated" ]]; then echo $'['$file_name'] Skipped because it was already up to date!\n';
    elif [[ $app_status == "outdated" && $6 != "noupdate" ]]; then ditto "$app_name" "/Applications/$app_name"; echo $'['$file_name'] Successfully updated!\n';
    elif [[ $app_status == "outdated" && $6 == "noupdate" ]]; then echo $'['$file_name'] This app cant be updated!\n'
    elif [[ $app_status == "uninstalled" ]]; then mv "$5$app_name" /Applications; echo $'['$file_name'] Succesfully installed!\n'; fi
    rm -rf "$file_name.tar.bz2" && rm -rf "$app_name";
  fi
}

###############################
#    Install selected apps    #
###############################
installApp "dmg" "Firefox" "Firefox.app" "http://download.mozilla.org/?product=firefox-latest&os=osx&lang=en-US" "" "" ""
installApp "dmg" "Chrome" "Google Chrome.app" "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg" "" "" ""
installApp "dmg" "Dropbox" "Dropbox.app" "https://www.dropbox.com/download?plat=mac" "" "" ""
installApp "dmg" "Alfred 3" "Alfred 3.app" "https://cachefly.alfredapp.com/Alfred_3.5.1_883.dmg" "" "" ""
installApp "zip" "SourceTree" "SourceTree.app" "https://downloads.atlassian.com/software/sourcetree/Sourcetree_2.6.3a.zip" "" "" ""
installApp "zip" "Dash" "Dash.app" "http://london.kapeli.com/Dash.zip" "" "" ""
installApp "zip" "Visual Studio Code" "Visual Studio Code.app" "http://go.microsoft.com/fwlink/?LinkID=620882" "" "" ""
installApp "dmg" "Docker" "Docker.app" "https://download.docker.com/mac/stable/Docker.dmg" "" "" ""
installApp "zip" "iTerm2" "iTerm.app" "https://iterm2.com/downloads/stable/latest" "" "" ""
installApp "zip" "1Password" "1Password 6.app" "https://d13itkw33a7sus.cloudfront.net/dist/1P/mac4/1Password-6.8.3.zip" "" "" ""
installApp "zip" "Spectacle" "Spectacle.app" "https://s3.amazonaws.com/spectacle/downloads/Spectacle+1.2.zip" "" "" ""
installApp "dmg" "Telegram" "Telegram.app" "https://tdesktop.com/mac" "" "" ""

rm -rf ~/gui-temp
