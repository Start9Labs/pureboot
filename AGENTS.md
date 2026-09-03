# PureBoot — Start9 fork

This is Start9's fork of [Purism's PureBoot](https://source.puri.sm/firmware/pureboot)
(itself a fork of [Heads](https://github.com/linuxboot/heads)). It builds the
firmware StartOS installs on the **Server Pure**, a Librem Mini v2. Only the
`librem_mini_v2` board is built and released here; the rest of the tree is
upstream's.

Read this file before touching anything. Upstream's build documentation is in
`README.md`; everything below is what differs from upstream.

## Branches and tags

- `start9` (default) — the latest Purism release plus the Start9 changes listed
  below. All work lands here.
- Every upstream branch and tag is mirrored as-is (`purism_next` is Purism's
  development branch, `Release-N` their release tags). Do not commit to them.
- `start9-X.Y.Z` tags are Start9 releases (see *Releasing*).

## Start9 changes

- `patches/coreboot-purism/` — applied by heads on top of the coreboot commit
  pinned in `modules/coreboot` (`coreboot-purism_commit_hash`):
  - `0001` adds an `enable_energy_perf_pref` / `energy_perf_pref_value`
    devicetree option to `soc/intel/cannonlake`, written after FSP-S because
    FSP-S owns HWP on this SoC.
  - `0002` sets it to `0xc0` on the Librem Mini variant, so Linux boots with
    `energy_performance_preference` = `balance_power` instead of
    `performance`.
- `config/coreboot-librem_mini_v2.config` — `CONFIG_USE_LEGACY_8254_TIMER=y`,
  as Release-29 had it. StartOS plays its startup, update and shutdown chimes
  through the PC speaker (`beep`), which is PIT channel 2; Purism's coreboot
  `320adcbe` (first shipped in Release 30) dropped the option to let a laptop
  reach S0ix, and cannonlake's `fsp_params.c` then clock-gates the 8254. That
  is the "Purism speaker bug" that kept StartOS on Release-29.
- `.github/workflows/build.yml` — builds the board in the heads image and
  publishes releases.
- `AGENTS.md`, `CLAUDE.md`, the fork notice in `README.md`.

## Building

Builds run inside the heads reproducible-build image the upstream CircleCI
config pins (`tlaurion/heads-dev-env`, tag in `.github/workflows/build.yml`).
A full build downloads and compiles the coreboot toolchain; measured at
12 minutes on 32 cores and 43 minutes on GitHub's 4-vCPU `ubuntu-latest`.

```bash
docker run --rm --user "$(id -u):$(id -g)" --tmpfs /tmp:exec,mode=1777 -e HOME=/tmp/home \
  -v "$PWD:$PWD" -w "$PWD" tlaurion/heads-dev-env:v0.1.9 \
  -- bash -c 'mkdir -p "$HOME" && exec ./build.sh librem_mini_v2'
```

The image's `/tmp` is writable by root only, and heads stages the initrd under
`mktemp -d`, so a non-root build brings its own `/tmp`. Running as root instead
works but leaves root-owned build trees behind. Tools the build produces, such
as `build/x86/coreboot-purism/librem_mini_v2/cbfstool`, link against the image's
loader and run only inside the same `docker run`.

`build.sh` runs `make BOARD=librem_mini_v2`, adds the firmware blob jail, and
writes one `.zip` per preconfiguration under `build/x86/librem_mini_v2/`:

| package | contents |
|---|---|
| `pureboot-librem_mini_v2-<ver>.zip` | stock PureBoot |
| `…-basic-<ver>.zip` | PureBoot Basic |
| `…-basic_usb_autoboot-<ver>.zip` | Basic + USB automatic boot + power on after power loss — **what StartOS installs** |
| `…-basic_usb_autoboot_blob_jail-<ver>.zip` | identical to `basic_usb_autoboot`; the blob jail is in every build now and enables itself on an AX200 |

The preconfigurations live in `preconfigure/librem_mini_v2/` and are baked into
CBFS as `heads/initrd/etc/config.user`.

To rebuild after editing a patch without rebuilding the toolchain, drop the
patch stamp and let make re-apply:

```bash
git -C build/x86/coreboot-purism reset -q --hard && rm -f build/x86/coreboot-purism/.patched
```

`modules/coreboot` reconfigures coreboot whenever the version string changes
(`.localversion`), so re-tagging and rebuilding in the same tree embeds the new
string; upstream heads keeps the `.config` from the first configure. CI also
leaves the coreboot board build directory out of its cache, so every CI ROM is
configured from scratch.

### Sources musl-cross-make fetches itself

musl-cross-make downloads its own gcc/binutils/musl/gmp tarballs and a pinned
`config.sub` into `build/x86/musl-cross-<version>/sources/`. The `config.sub`
comes from savannah's gitweb, which answers 404 to GitHub Actions runners, so
CI copies `.github/musl-cross-make/config.sub` there before the build and,
after it, checks the file against the sha1 musl-cross-make pins
(`build/x86/musl-cross-*/hashes/config.sub.*.sha1`). Bumping
`musl-cross_version` may move that pin; refresh the vendored copy from
`https://git.savannah.gnu.org/cgit/config.git/plain/config.sub?id=<rev>` when
the check fails.

## Version string

heads names every artifact and the SMBIOS BIOS version after
`git describe --abbrev=7 --tags --dirty`, prefixed with `BRAND_NAME`
(`PureBoot`), so a build of tag `start9-30.1.1` reports
`PureBoot-start9-30.1.1` to `dmidecode -s bios-version`.

StartOS decides whether to flash from that string
(`shared-libs/crates/start-core/src/firmware.rs` in start-technologies):
it strips the `semver-prefix` in `firmware.json`, splits the rest on `.`,
**drops every segment that is not a plain integer**, and compares the first
three as a semver. Consequences:

- A release tag is `start9-X.Y.Z`: `X.Y` is the Purism release it is based on,
  `Z` the Start9 revision on top of it (`start9-30.1.1` is the first build on
  `Release-30.1`; `Release-31` would be followed by `start9-31.0.1`).
- Nothing else goes in a release tag: `start9-30.1.1-rc1` parses as `30.1.0`
  because `1-rc1` is dropped, so the release would flash over it.
- `BRAND_NAME` stays `PureBoot`. The `PureBoot-start9-` prefix is what
  `firmware.json` matches, and `PureBoot-Release-` is how StartOS recognises a
  Purism-built firmware to replace.

## Releasing

1. Merge or rebase onto the Purism release you want (see *Syncing*), build
   locally, and test on a Server Pure.
2. Tag the `start9` head: `git tag start9-X.Y.Z && git push origin start9-X.Y.Z`.
3. CI builds it and publishes a GitHub Release carrying the `.zip` packages, a
   `.rom.gz` of each (what StartOS downloads at ISO build time), heads'
   `hashes.txt`, and `SHA256SUMS`. Builds run on `ubuntu-latest`; the
   `workflow_dispatch` `runner: fast` option asks for `ubuntu-24.04-32-cores`,
   which only works once an org owner grants this repository that runner
   group — a job requesting a label it cannot get stays queued indefinitely.
4. Point StartOS at it: in start-technologies edit
   `projects/start-os/build/lib/firmware.json` — the `id` is the `.rom.gz`
   basename without extension, `url` the release asset, `shasum` from
   `SHA256SUMS`, and raise the `PureBoot-start9-` entry's `semver-range` to
   `<X.Y.Z`. `download-firmware.sh` fetches and verifies it during the ISO
   build; `start-init` flashes it on the next boot of any matching machine.
   Update `projects/start-os/docs/src/firmware-pure.md` and the changelog in
   the same PR.

Pushes to `start9` and pull requests build too (without publishing) so a
broken tree is caught before it is tagged.

## Syncing with Purism

```bash
git remote add purism https://source.puri.sm/firmware/pureboot.git
git fetch purism --tags
git push origin 'refs/remotes/purism/*:refs/heads/*' --tags   # refresh the mirror
git checkout start9 && git merge Release-N
```

After a merge, check that `patches/coreboot-purism/*.patch` still apply to the
new `coreboot-purism_commit_hash` (`make BOARD=librem_mini_v2` fails at the
patch step otherwise) and re-read `preconfigure/librem_mini_v2/` and
`blobs/librem_jail/README` for changes to the variant StartOS installs.

## Upstreaming

The EPP option is written to be upstreamable: `0001` mirrors what
`soc/intel/alderlake` already carries, and `0002` is a two-line devicetree
change. Offer both to Purism (`firmware/coreboot` on source.puri.sm) so the
patch directory can shrink to nothing.
