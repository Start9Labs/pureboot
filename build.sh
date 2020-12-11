#!/bin/bash

set -e

first() {
	echo "$1"
}

all_boards=('librem_13v2' 'librem_15v3' \
			'librem_13v4' 'librem_15v4' \
			'librem_mini' 'librem_mini_v2' \
			'librem_14' "librem_l1um")

if [ -z "$1" ]; then
	build_targets=("${all_boards[@]}");
else
	build_targets=("$@")
fi

add_device_firmware() {
	ROM="$(realpath "$1")"

	cbfstool="$(realpath "$(first build/x86/coreboot-*/"$board"/cbfstool)")"

	(
		local compress_args compress_suffix
		cd blobs/librem_jail

		for firmware in * */*; do
			# the glob picks up directories
			if [ ! -f "$firmware" ]; then
				continue
			fi

			if [ "$(stat -c "%s" "$firmware")" -ge 1024 ]; then
				compress_args=(-c lzma)
				compress_suffix=".lzma"
			else
				compress_args=()
				compress_suffix=""
			fi

			"$cbfstool" "$ROM" add -t raw "${compress_args[@]}" \
				-n "firmware/$firmware$compress_suffix" \
				-f "$firmware"
		done
	)
}

for board in "${build_targets[@]}"
do
	make BOARD=$board
	
	# If any preconfigurations exist for this board, create a ROM for each
	for config in "preconfigure/$board"/*; do
		if ! [ -f "$config" ]; then
			continue;
		fi
		
		config_name="$(basename "$config")"
		rom_path="build/x86/$board"
		rom_version="$(git describe --abbrev=7 --tags --dirty)"
		base_rom_name="pureboot-$board-$rom_version.rom"
		config_rom_name="pureboot-$board-$config_name-$rom_version.rom"
		cbfstool="$(first build/x86/coreboot-*/"$board"/cbfstool)"
		
		cp "$rom_path/$base_rom_name" "$rom_path/$config_rom_name"
		"$cbfstool" "$rom_path/$config_rom_name" add -n heads/initrd/etc/config.user -f "$config" -t raw
		echo "Built preconfigured ROM $rom_path/$config_rom_name"

		# Add device firmware blobs to configurations with blob jail
		if grep -q -E '\bCONFIG_SUPPORT_BLOB_JAIL="?y"?$' "$config"; then
			add_device_firmware "$rom_path/$config_rom_name"
		fi
	done
done
