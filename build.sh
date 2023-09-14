#!/bin/bash

set -e

first() {
	echo "$1"
}

all_boards=('librem_13v2' 'librem_15v3' \
			'librem_13v4' 'librem_15v4' \
			'librem_mini' 'librem_mini_v2' \
			'librem_14' 'librem_l1um' \
			'librem_l1um_v2')

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
		cd blobs/librem_jail/"$board"

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
	# L1UM uses coreboot 4.11, which does not build with make 4.3+.  Build
	# and use make 4.2.1 for this board.
	if [ "$board" = "librem_l1um" ]; then
		make -f make421.makefile
		PATH="$(pwd)/build/make-4.2.1:$PATH" make BOARD="$board"
	else
		make BOARD="$board"
	fi

	rom_path="build/x86/$board"
	rom_version="$(git describe --abbrev=7 --tags --dirty)"
	base_rom_name="pureboot-$board-$rom_version.rom"

	# If the board config supports blob jail, add firmware to the base ROM
	if grep -q -E '\bCONFIG_SUPPORT_BLOB_JAIL="?y"?$' "boards/$board/$board.config"; then
		add_device_firmware "$rom_path/$base_rom_name"
	fi
	
	# If any preconfigurations exist for this board, create a ROM for each
	for config in "preconfigure/$board"/*; do
		if ! [ -f "$config" ]; then
			continue;
		fi
		
		config_name="$(basename "$config")"
		config_rom_name="pureboot-$board-$config_name-$rom_version.rom"
		cbfstool="$(first build/x86/coreboot-*/"$board"/cbfstool)"
		
		cp "$rom_path/$base_rom_name" "$rom_path/$config_rom_name"
		"$cbfstool" "$rom_path/$config_rom_name" add -n heads/initrd/etc/config.user -f "$config" -t raw
		echo "Built preconfigured ROM $rom_path/$config_rom_name"

		# If the configuration enables blob jail (in which case the
		# base board does not, this is a variant), add device firmware
		if grep -q -E '\bCONFIG_SUPPORT_BLOB_JAIL="?y"?$' "$config"; then
			add_device_firmware "$rom_path/$config_rom_name"
		fi
	done
done
