#!/bin/bash

set -e

all_boards=('librem_13v2' 'librem_15v3' \
			'librem_13v4' 'librem_15v4' \
			'librem_mini' 'librem_mini_v2' \
			'librem_14' "librem_l1um")

if [ -z "$1" ]; then
	build_targets=("${all_boards[@]}");
else
	build_targets=($@)
fi

GIT_VERSION=$(git describe --tags --dirty)

for board in ${build_targets[@]}
do
	make BOARD=$board
	if [[ "$board" = "librem_14" || "$board" = "librem_mini_v2" ]]; then
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
			-n firmware/iwlwifi-cc-a0-59.ucode.lzma \
			-f blobs/librem_jail/iwlwifi-cc-a0-59.ucode
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
			-n firmware/intel/ibt-20-1-3.ddc -f blobs/librem_jail/intel/ibt-20-1-3.ddc
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
			-n firmware/intel/ibt-20-1-3.sfi.lzma -f blobs/librem_jail/intel/ibt-20-1-3.sfi 
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
			-n firmware/ar3k/AthrBT_0x11020100.dfu.lzma -f blobs/librem_jail/ar3k/AthrBT_0x11020100.dfu
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
			-n firmware/ar3k/ramps_0x11020100_40.dfu.lzma -f blobs/librem_jail/ar3k/ramps_0x11020100_40.dfu
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
			-n firmware/hashes -f blobs/librem_jail/hashes
		cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
			-n firmware/README -f blobs/librem_jail/README
	fi
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom print
done
