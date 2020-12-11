#!/usr/bin/bash
set -e

# use TERM to exit on error
trap "exit 1" TERM
export TOP_PID=$$

die () {
	local msg=$1

	if [ ! -z "$msg" ]; then
	echo ""
		echo -e "$msg"
	echo ""
	fi
	kill -s TERM $TOP_PID
	exit 1
}

# boards to build
boards=("librem_13v2" "librem_15v3" "librem_13v4" "librem_15v4" \
	"librem_mini" "librem_mini_v2" "librem_l1um" "librem_14")

# check release tags
TAG=$(git describe --tags --dirty)
if [[ "$TAG" == *"dirty"* ]]; then
	echo "Error: branch must be clean to perform a release build"
	exit 1
fi

echo "Creating new branches..."

# create branch in releases repo
(
	cd ../releases
	if ! git checkout -b Pureboot-$TAG >/dev/null ; then
		die "Error creating release branch Pureboot-$TAG -- already exists?"
	fi
	git fetch >/dev/null 2>&1
	git reset --hard origin/master >/dev/null 2>&1
)
# create branch in utility repo
(
	cd ../utility
	if ! git checkout -b Pureboot-$TAG  > /dev/null; then
		die "Error creating utility branch Pureboot-$TAG -- already exists?"
	fi
	git fetch >/dev/null 2>&1
	git reset --hard origin/master >/dev/null 2>&1

	# update version string
	sed -i "s/^PUREBOOT_VERSION.*$/PUREBOOT_VERSION=\"${TAG}\"/" coreboot_util.sh
)

for board in ${boards[@]}
do
	filename="pureboot-${board}-${TAG}.rom"
	filepath="build/${board}/"
	rm ${filepath}${filename} 2>/dev/null | true

	# build board
	make BOARD=${board}

	# compress
	gzip -k ${filepath}${filename}

	# get hash
	ZIP_SHA=$(sha256sum ${filepath}${filename}.gz | awk '{print $1}')

	# update in releases repo
	mkdir -p ../releases/${board}/ 2>/dev/null | true
	rm ../releases/${board}/pureboot-${board}* 2>/dev/null | true
	mv ${filepath}${filename}.gz ../releases/${board}/

	# update board hash in coreboot_util.sh
	brd=`echo $board | cut -f2-3 -d'_'`
	sed -i "s/^COREBOOT_HEADS_IMAGE_${brd}_SHA.*$/COREBOOT_HEADS_IMAGE_${brd}_SHA=\"${ZIP_SHA}\"/" ../utility/coreboot_util.sh
done

# commit new boards in releases
(
	cd ../releases
	if ! git checkout Pureboot-$TAG >/dev/null 2>&1; then
		die "Error checking out release branch Pureboot-$TAG"
	fi
	# prompt to update changelog
	echo -e "\nPlease update the releases changelog, then press enter to continue"
	read -rp "" discard

	# add files, do commit
	git add librem_*/pureboot-* >/dev/null 2>&1
	git commit -s -S -a -m "Update Pureboot images to $TAG"
	# push branch
	if ! git push origin Pureboot-$TAG >/dev/null 2>&1; then
		echo -e "\nError pushing release branch Pureboot-$TAG\n"
	fi

	# get releases hash
	REL_SHA=$(git rev-parse --verify HEAD)
	# inject into coreboot_util
	sed -i "s/^RELEASES_GIT_HASH.*$/RELEASES_GIT_HASH=\"${REL_SHA}\"/" ../utility/coreboot_util.sh
)


# commit updates to coreboot_util
(
	cd ../utility
	if ! git checkout Pureboot-$TAG >/dev/null 2>&1 ; then
		die "Error checking out utility branch Pureboot-$TAG"
	fi
	### add files, do commit
	git add coreboot_util.sh >/dev/null 2>&1
	git commit -s -S -m "Update Pureboot images to $TAG" -m "Update releases repo hash, filenames/hashes."
	# push branch
	if ! git push origin Pureboot-$TAG >/dev/null 2>&1; then
		echo -e "\nError pushing release branch Pureboot-$TAG\n"
	fi
)

# push branch, tag itself
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if ! git push -f origin $BRANCH >/dev/null; then
	echo -e "\nError pushing branch $BRANCH\n"
fi
if ! git push origin $TAG >/dev/null; then
	echo -e "\nError pushing Pureboot tag $TAG\n"
fi

echo -e "\nPureboot release builds successfully built and branches added\n"
