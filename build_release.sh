#!/usr/bin/bash
set -e

# use TERM to exit on error
trap "exit 1" TERM
export TOP_PID=$$

SCRATCHDIR="$(mktemp -d)"
trap 'rm -rf -- "$SCRATCHDIR"' EXIT

die () {
	local msg=$1

	if [ -n "$msg" ]; then
		echo ""
		echo -e "$msg"
		echo ""
	fi >&2
	kill -s TERM $TOP_PID
	exit 1
}

pause () {
	echo -e "\n$1"
	read -r _
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

# The release tag must point at HEAD - if there are extra commits after the tag,
# we'd get <tag>-<commits>-g<sha>.
if [ -z "$(git tag -l "$TAG" --points-at HEAD)" ]; then
	echo "Error: Tag doesn't point to HEAD - got description '${TAG}'" >&2
	# The solution currently is to reset the tag to point at the new HEAD
	# for RC2, RC3, etc.  Ideally we would wait to tag until the final RC
	# has passed testing though so we are not moving tags that were
	# published, this will need a bit more rework.
	echo "Reset tag to HEAD and try again" >&2
	exit 1
fi

echo "Creating new branches..."

# Create or check out a branch, and print the number of commits on that branch
# not included in origin/master.
checkout_release_branch() {
	REPO_DIR="$1"
	RELEASE_BRANCH="$2"

	if [ -n "$(git -C "$REPO_DIR" status --porcelain)" ]; then
		die "Repo $REPO_DIR is not clean, commit/stash changes and try again"
	fi
	if ! git -C "$REPO_DIR" checkout "$RELEASE_BRANCH" 2>/dev/null; then
		git -C "$REPO_DIR" checkout --detach origin/master
		git -C "$REPO_DIR" checkout -b "$RELEASE_BRANCH"
	fi
	git -C "$REPO_DIR" rev-list --count origin/master.."$RELEASE_BRANCH"
}

# Create branches in releases and utility, get the number of commits in each to
# determine the RC number
RELEASE_BRANCH="PureBoot-$TAG"
RELEASES_RC_COMMITS="$(checkout_release_branch ../releases "$RELEASE_BRANCH")"
UTILITY_RC_COMMITS="$(checkout_release_branch ../utility "$RELEASE_BRANCH")"

# The repos must have the same number of commits so far, or we wouldn't know
# what RC number to use
if [ "$RELEASES_RC_COMMITS" -ne "$UTILITY_RC_COMMITS" ]; then
	echo "releases and utility have different commit counts in branch $RELEASE_BRANCH" >&2
	echo "($RELEASES_RC_COMMITS vs. $UTILITY_RC_COMMITS)" >&2
	echo "Can't determine RC number, clean up and try again" >&2
	exit 1
fi

RC_NUM="$(("$RELEASES_RC_COMMITS" + 1))"
echo "Building $RELEASE_BRANCH/RC$RC_NUM..."

for board in "${boards[@]}"
do
	filename="pureboot-${board}-${TAG}.rom"
	filepath="build/x86/${board}/"
	rm "${filepath}${filename}" 2>/dev/null || true

	# build board
	while ! make BOARD=${board}
	do
		read -rp "Build failed - retry?" retry
		if [[ "$retry" != "Y" && "$retry" != "y" ]] ; then
			die "user aborted"
		fi
	done

	# compress
	gzip -k "${filepath}${filename}"

	# get hash
	ZIP_SHA=$(sha256sum "${filepath}${filename}.gz" | awk '{print $1}')

	# update in releases repo
	mkdir -p "../releases/${board}/" 2>/dev/null || true
	rm "../releases/${board}/pureboot-${board}"* 2>/dev/null || true
	mv "${filepath}${filename}.gz" "../releases/${board}/"

	# update board hash in coreboot_util.sh
	brd="$(echo "$board" | cut -f2-3 -d'_')"
	sed -i "s/^COREBOOT_HEADS_IMAGE_${brd}_SHA.*$/COREBOOT_HEADS_IMAGE_${brd}_SHA=\"${ZIP_SHA}\"/" ../utility/coreboot_util.sh
done

# Prepare commit message template
COMMITMSG_TMP="$SCRATCHDIR/commitmsg"
echo "Update PureBoot images to $TAG/RC$RC_NUM" >"$COMMITMSG_TMP"
# For RC1, there are no prior RCs, so just use the message as-is.
if [ "$RC_NUM" -eq 1 ]; then
	COMMITMSG_ARGS=("-F" "$COMMITMSG_TMP")
else
	# For RC2+, include the changes from the prior RC, this must be edited
	# during git-commit (or git will abort)
	echo "" >>"$COMMITMSG_TMP"
	echo "<Changes from prior RC>" >>"$COMMITMSG_TMP"
	COMMITMSG_ARGS=("-t" "$COMMITMSG_TMP")
fi

# commit new boards in releases
(
	cd ../releases
	if ! git checkout "$RELEASE_BRANCH" >/dev/null 2>&1; then
		die "Error checking out release branch $RELEASE_BRANCH"
	fi
	# prompt to update changelog
	pause "Please update the releases changelog, then press enter to continue"

	# add files, do commit
	git add librem_*/pureboot-* >/dev/null 2>&1
	git commit -s -S -a "${COMMITMSG_ARGS[@]}"

	# get releases hash
	REL_SHA=$(git rev-parse --verify HEAD)
	# inject into coreboot_util
	sed -i "s/^RELEASES_GIT_HASH.*$/RELEASES_GIT_HASH=\"${REL_SHA}\"/" ../utility/coreboot_util.sh
)

# Use the same message for utility (the same RC notes for RC2+)
git -C ../releases log --format=%B -n 1 HEAD >"$COMMITMSG_TMP"

# commit updates to coreboot_util
(
	cd ../utility
	if ! git checkout "$RELEASE_BRANCH" >/dev/null 2>&1 ; then
		die "Error checking out utility branch $RELEASE_BRANCH"
	fi
	# update version string
	sed -i "s/^PUREBOOT_VERSION.*$/PUREBOOT_VERSION=\"${TAG}\"/" coreboot_util.sh
	### add files, do commit
	git add coreboot_util.sh >/dev/null 2>&1
	git commit -s -S -F "$COMMITMSG_TMP"
)

pause "Ready to push $RELEASE_BRANCH/RC$RC_NUM, press enter to continue"

# Push everything last
if ! git -C ../releases push origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
	echo -e "\nError pushing utility branch $TAG\n"
fi
if ! git -C ../utility push origin "$RELEASE_BRANCH" >/dev/null 2>&1; then
	echo -e "\nError pushing releases branch $TAG\n"
fi

# push branch, tag itself
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if ! git push -f origin "$BRANCH" >/dev/null; then
	echo -e "\nError pushing branch $BRANCH\n"
fi
if ! git push origin "$TAG" -f >/dev/null; then
	echo -e "\nError pushing PureBoot tag $TAG\n"
fi

echo -e "\nPureBoot release builds successfully built and branches added\n"
