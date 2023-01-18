#! /bin/sh

set -e -o pipefail

. /etc/gui_functions

TMP_ROM=/tmp/extract_console_rom.bin
TMP_CONSOLE=/tmp/extract_console_console.log

rm -f "$TMP_ROM" "$TMP_CONSOLE"

mount_usb
mount -o remount,rw /media
/bin/flash.sh -r "$TMP_ROM"

# Hardcoded offset of the CONSOLE section, check with cbfstool <rom> layout -w
# Determining this properly requires finding and parsing the FMAP header
dd if="$TMP_ROM" of="$TMP_CONSOLE" bs=1M count=1 skip=6225920 iflag=skip_bytes
cp "$TMP_CONSOLE" /media/console.log
sync

echo "Created console.log on USB drive."
echo "Please reboot into the OS and provide this file for troubleshooting."
