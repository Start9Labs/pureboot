#!/bin/bash

set -e

make BOARD=librem_13v2 &&
make BOARD=librem_15v3 &&
make BOARD=librem_13v4 &&
make BOARD=librem_15v4 &&
make BOARD=librem_mini &&
make BOARD=librem_mini_v2 &&
make BOARD=librem_14 &&
make BOARD=librem_l1um &&

echo -e "\nAll Librem boards built successfully"
