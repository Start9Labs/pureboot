# This makefile is used to download, patch, configure, and build make 4.2.1,
# which is required for coreboot 4.11 used for Librem L1UM.

make_version := 4.2.1
make_dir := make-$(make_version)
make_tar := make-$(make_version).tar.bz2

make_url := http://gnu.mirror.constant.com/make/$(make_tar)
make_hash := d6e262bf3601b42d2b1e4ef8310029e1dcf20083c5446b4b7aa67081fdffc589

pwd := $(shell pwd)
build := $(pwd)/build
packages := $(pwd)/packages

.DEFAULT_GOAL := default

$(packages)/$(make_tar):
	wget -O "$@.tmp" "$(make_url)"
	if ! echo "$(make_hash)  $@.tmp" | sha256sum --check -; then \
		exit 1 ; \
	fi
	mv "$@.tmp" "$@"

$(build)/$(make_dir)/.extract: $(packages)/$(make_tar)
	tar xf "$<" -C "$(build)"
	touch "$@"

$(build)/$(make_dir)/.patch: $(build)/$(make_dir)/.extract
	( cd "$(dir $@)" ; patch -p1 ) < "patches/make-$(make_version).patch"
	touch "$@"

$(build)/$(make_dir)/.configured: $(build)/$(make_dir)/.patch
	cd "$(dir $@)"; ./configure
	touch "$@"

$(build)/$(make_dir)/make: $(build)/$(make_dir)/.configured
	make -C "$(dir $@)" $(MAKE_JOBS)

default: $(build)/$(make_dir)/make
