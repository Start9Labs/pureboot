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
	# L1UM uses coreboot 4.11, which does not build with make 4.3+.  Build
	# and use make 4.2.1 for this board.
	if [ "$board" = "librem_l1um" ]; then
		make -f make421.makefile
		PATH="$(pwd)/build/make-4.2.1:$PATH" make BOARD="$board"
	else
		make BOARD="$board"
	fi
done
