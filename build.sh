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
	done
done
