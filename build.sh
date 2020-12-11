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
done
