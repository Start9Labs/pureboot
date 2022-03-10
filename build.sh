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
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/iwlwifi-9260-th-b0-jf-b0-46.ucode.lzma \
		-f blobs/librem_jail/iwlwifi-9260-th-b0-jf-b0-46.ucode
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/iwlwifi-cc-a0-59.ucode.lzma \
		-f blobs/librem_jail/iwlwifi-cc-a0-59.ucode
#	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
#		-n firmware/iwlwifi-cc-a0-63.ucode.lzma \
#		-f blobs/librem_jail/iwlwifi-cc-a0-63.ucode
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/iwlwifi-ty-a0-gf-a0-63.ucode.lzma \
		-f blobs/librem_jail/iwlwifi-ty-a0-gf-a0-63.ucode
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/iwlwifi-ty-a0-gf-a0.pnvm.lzma \
		-f blobs/librem_jail/iwlwifi-ty-a0-gf-a0.pnvm
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
		-n firmware/intel/ibt-20-1-3.ddc -f blobs/librem_jail/intel/ibt-20-1-3.ddc
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/intel/ibt-20-1-3.sfi.lzma -f blobs/librem_jail/intel/ibt-20-1-3.sfi 
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
		-n firmware/intel/ibt-18-16-1.ddc -f blobs/librem_jail/intel/ibt-18-16-1.ddc
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/intel/ibt-18-16-1.sfi.lzma -f blobs/librem_jail/intel/ibt-18-16-1.sfi 
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
		-n firmware/intel/ibt-0041-0041.ddc -f blobs/librem_jail/intel/ibt-0041-0041.ddc
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/intel/ibt-0041-0041.sfi.lzma -f blobs/librem_jail/intel/ibt-0041-0041.sfi
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/ar3k/AthrBT_0x11020100.dfu.lzma -f blobs/librem_jail/ar3k/AthrBT_0x11020100.dfu
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw -c lzma \
		-n firmware/ar3k/ramps_0x11020100_40.dfu.lzma -f blobs/librem_jail/ar3k/ramps_0x11020100_40.dfu
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
		-n firmware/hashes -f blobs/librem_jail/hashes
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom add -t raw \
		-n firmware/README -f blobs/librem_jail/README
	cbfstool build/$board/pureboot-$board-$GIT_VERSION.rom print
done
