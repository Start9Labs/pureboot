# heads-packages

This tag exists only to carry the `heads-packages` release: a mirror of every
source tarball a `librem_mini_v2` build downloads, named as heads saves it under
`packages/x86/`. `bin/fetch_source_archive.sh` on the `start9` branch lists the
release as a backup mirror beside Purism's `storage.puri.sm/heads-packages/`,
and checks each file against the hash its module pins.

The commit has no parents and is not in `start9`'s history, so `git describe`
never picks the tag up.