#!/bin/bash

set -e

first() {
	echo "$1"
}

die() {
	echo "$@" >&2
	exit 1
}

# use to select a single item matching a glob,
# dies if glob matches nothing or more than one thing
only() {
	[ "$#" -gt 1 ] && die "More than one item found:" "$@"
	[ ! -e "$1" ] && die "No matches: $1"
	echo "$1"
}

# librem_l1um is most likely to break due to coreboot 4.11,
# build that first.
all_boards=(
	'librem_l1um' 'librem_l1um_v2' \
	'librem_13v2' 'librem_15v3' \
	'librem_13v4' 'librem_15v4' \
	'librem_mini' 'librem_mini_v2' \
	'librem_14' 'librem_11' 'librem_16'
)

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

# After adding files to ROMs, we must build update packages containing them.
# This directory is used to stage the package contents.
BUILD_PKG_DIR="$(pwd)/build/pkg"

# Initialize the package with a new ROM (cleans anything from a prior package).
# A different basename can be specified, such as to change the name for a
# preconfiguration.
init_build_pkg() {
	local ROM PKG_BASENAME
	ROM="$1"
	PKG_BASENAME="$2"

	# Default to the ROM basename
	if [ -z "$PKG_BASENAME" ]; then
		PKG_BASENAME="$(basename "$ROM" .rom)"
	fi

	rm -rf "$BUILD_PKG_DIR"
	mkdir -p "$BUILD_PKG_DIR"
	cp "$ROM" "$BUILD_PKG_DIR/$PKG_BASENAME.rom"
}

# Create a package from the staged contents.  Specify the directory where the
# package will go, the filename is detected from the ROM basename.
create_pkg() {
	local PKG_DIR
	PKG_DIR="$1"

	PKG_DIR="$(realpath "$PKG_DIR")" # Absolute path

	(
		local ROM BASENAME
		cd "$BUILD_PKG_DIR"
		ROM="$(only ./*.rom)"
		BASENAME="$(basename "$ROM" .rom)"
		rm -f sha256sum.txt
		sha256sum -- * >sha256sum.txt
		zip -9 "$PKG_DIR/$BASENAME.zip" ./*
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
		# Update the built ROM in-place, then re-package.  The in-place
		# ROM is used again if there are preconfigurations.
		add_device_firmware "$rom_path/$base_rom_name"
		init_build_pkg "$rom_path/$base_rom_name"
		create_pkg "$rom_path"
	fi
	
	# If any preconfigurations exist for this board, create a ROM for each
	for config in "preconfigure/$board"/*; do
		if ! [ -f "$config" ]; then
			continue;
		fi
		
		config_name="$(basename "$config")"
		config_rom_basename="pureboot-$board-$config_name-$rom_version"
		cbfstool="$(first build/x86/coreboot-*/"$board"/cbfstool)"

		init_build_pkg "$rom_path/$base_rom_name" "$config_rom_basename"
		"$cbfstool" "$BUILD_PKG_DIR/$config_rom_basename.rom" add -n heads/initrd/etc/config.user -f "$config" -t raw
		create_pkg "$rom_path"
		echo "Built preconfigured ROM package $rom_path/$config_rom_basename.zip"
	done
done
