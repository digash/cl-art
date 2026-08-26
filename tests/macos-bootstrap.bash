#!/usr/bin/env bash

set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd -- "$test_dir/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/cl-art-bootstrap-test.XXXXXX")

cleanup() {
  rm -rf -- "$test_root"
}
trap cleanup EXIT

fake_bin=$test_root/fake-bin
fake_brew_log=$test_root/brew.log
fake_sbcl_log=$test_root/sbcl.log
state_root=$test_root/state
art_bin_dir=$test_root/local-bin
quicklisp_home=$test_root/quicklisp
mkdir -p -- "$fake_bin" "$state_root/guix-sync" "$state_root/mac-sync" \
  "$art_bin_dir" "$quicklisp_home"

cat > "$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${CL_ART_FAKE_BREW_LOG:?}"
case ${1:-} in
  bundle)
    exit 0
    ;;
  list)
    formula=${3:-}
    [[ $formula != ${CL_ART_FAKE_MISSING:-} ]]
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod 0755 "$fake_bin/brew"

cat > "$fake_bin/sbcl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode=${CL_ART_QUICKLISP_MODE:-installer}
printf '%s|%s\n' "$mode" "$*" >> "${CL_ART_FAKE_SBCL_LOG:?}"
if [[ ${CL_ART_FAKE_INSTALL_SETUP:-0} == 1 && \
      -n ${CL_ART_QUICKLISP_HOME:-} ]]; then
  mkdir -p -- "$CL_ART_QUICKLISP_HOME"
  printf 'fake Quicklisp setup\n' > "$CL_ART_QUICKLISP_HOME/setup.lisp"
fi
if [[ $mode == ${CL_ART_FAKE_SBCL_FAIL_MODE:-__never__} ]]; then
  exit 1
fi
EOF
chmod 0755 "$fake_bin/sbcl"
printf 'existing Quicklisp setup\n' > "$quicklisp_home/setup.lisp"
cp -p -- "$quicklisp_home/setup.lisp" "$test_root/setup.original"

modern_state=$state_root/guix-sync/brew-managed
legacy_state=$state_root/mac-sync/brew-managed
cat > "$modern_state" <<'EOF'
aspell
sbcl
sdl2-compat
sdl2_image
tree
EOF
cat > "$legacy_state" <<'EOF'
sdl2_ttf
zstd
EOF
cp -p -- "$modern_state" "$test_root/modern.original"
cp -p -- "$legacy_state" "$test_root/legacy.original"
printf 'old art command\n' > "$art_bin_dir/art"

run_bootstrap() {
  PATH="$fake_bin:$PATH" \
  XDG_STATE_HOME="$state_root" \
  CL_ART_BIN_DIR="$art_bin_dir" \
  CL_ART_QUICKLISP_HOME="$quicklisp_home" \
  CL_ART_SBCL="$fake_bin/sbcl" \
  CL_ART_BOOTSTRAP_TESTING=1 \
  CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
  CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
    bash "$repo_root/macos/bootstrap" "$@"
}

run_bootstrap --adopt-only

for formula in sdl2-compat sdl2_image sdl2_ttf; do
  if grep -Fqx -- "$formula" "$modern_state" || \
     grep -Fqx -- "$formula" "$legacy_state"; then
    printf 'formula remained under guix-sync ownership: %s\n' "$formula" >&2
    exit 1
  fi
done
grep -Fqx -- aspell "$modern_state"
grep -Fqx -- sbcl "$modern_state"
grep -Fqx -- tree "$modern_state"
grep -Fqx -- zstd "$legacy_state"
cmp -s -- "$test_root/modern.original" "${modern_state}.before-cl-art"
cmp -s -- "$test_root/legacy.original" "${legacy_state}.before-cl-art"
cmp -s -- "$repo_root/bin/art" "$art_bin_dir/art"
cmp -s -- "$test_root/setup.original" "$quicklisp_home/setup.lisp"
[[ -x $art_bin_dir/art ]]
grep -Fqx -- 'old art command' "${art_bin_dir}/art.before-cl-art"

# A second adoption is idempotent and does not replace the backups.
run_bootstrap --adopt-only
cmp -s -- "$test_root/modern.original" "${modern_state}.before-cl-art"
cmp -s -- "$test_root/legacy.original" "${legacy_state}.before-cl-art"

# The normal install path runs Brewfile reconciliation, and check validates the
# completed handoff without changing it.
: > "$fake_brew_log"
run_bootstrap --install
grep -Fqx -- "bundle --file=$repo_root/macos/Brewfile" "$fake_brew_log"
grep -Fq -- "preload|" "$fake_sbcl_log"
grep -Fq -- '--dynamic-space-size 4096' "$fake_sbcl_log"
: > "$fake_brew_log"
run_bootstrap --check
if grep -Fq -- 'bundle' "$fake_brew_log"; then
  printf 'check mode unexpectedly invoked brew bundle\n' >&2
  exit 1
fi
grep -Fq -- "check|" "$fake_sbcl_log"
cmp -s -- "$test_root/setup.original" "$quicklisp_home/setup.lisp"

# A fresh Quicklisp install requires a caller-supplied installer and matching
# checksum.  Fake SBCL creates setup.lisp, so this path never reaches a network.
installer=$test_root/quicklisp-installer.lisp
printf 'pinned fake Quicklisp installer\n' > "$installer"
installer_sum=$(shasum -a 256 -- "$installer")
installer_sum=${installer_sum%% *}

# A fresh-install dry run validates the pinned installer but neither expects
# setup.lisp to exist yet nor invokes SBCL to create it.
dry_quicklisp=$test_root/dry-quicklisp
PATH="$fake_bin:$PATH" \
XDG_STATE_HOME="$test_root/dry-state" \
CL_ART_BIN_DIR="$test_root/dry-bin" \
CL_ART_QUICKLISP_HOME="$dry_quicklisp" \
CL_ART_QUICKLISP_INSTALLER="$installer" \
CL_ART_QUICKLISP_INSTALLER_SHA256="$installer_sum" \
CL_ART_SBCL="$fake_bin/sbcl" \
CL_ART_BOOTSTRAP_TESTING=1 \
CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
  bash "$repo_root/macos/bootstrap" --adopt-only --no-install-art --dry-run
[[ ! -e $dry_quicklisp ]]

fresh_quicklisp=$test_root/fresh-quicklisp
fresh_state_root=$test_root/fresh-state
fresh_bin_dir=$test_root/fresh-bin
PATH="$fake_bin:$PATH" \
XDG_STATE_HOME="$fresh_state_root" \
CL_ART_BIN_DIR="$fresh_bin_dir" \
CL_ART_QUICKLISP_HOME="$fresh_quicklisp" \
CL_ART_QUICKLISP_INSTALLER="$installer" \
CL_ART_QUICKLISP_INSTALLER_SHA256="$installer_sum" \
CL_ART_SBCL="$fake_bin/sbcl" \
CL_ART_BOOTSTRAP_TESTING=1 \
CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
CL_ART_FAKE_INSTALL_SETUP=1 \
  bash "$repo_root/macos/bootstrap" --adopt-only --no-install-art
[[ -f $fresh_quicklisp/setup.lisp ]]
grep -Fq -- "installer|" "$fake_sbcl_log"
grep -Fq -- "preload|" "$fake_sbcl_log"

# A mismatched checksum stops before SBCL, Quicklisp, art, or state changes.
bad_quicklisp=$test_root/bad-quicklisp
if PATH="$fake_bin:$PATH" \
   XDG_STATE_HOME="$test_root/bad-state" \
   CL_ART_BIN_DIR="$test_root/bad-bin" \
   CL_ART_QUICKLISP_HOME="$bad_quicklisp" \
   CL_ART_QUICKLISP_INSTALLER="$installer" \
   CL_ART_QUICKLISP_INSTALLER_SHA256=0000000000000000000000000000000000000000000000000000000000000000 \
   CL_ART_SBCL="$fake_bin/sbcl" \
   CL_ART_BOOTSTRAP_TESTING=1 \
   CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
   CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
   CL_ART_FAKE_INSTALL_SETUP=1 \
     bash "$repo_root/macos/bootstrap" --adopt-only --no-install-art; then
  printf 'bootstrap unexpectedly accepted a bad Quicklisp checksum\n' >&2
  exit 1
fi
[[ ! -e $bad_quicklisp/setup.lisp ]]

# An incomplete non-empty Quicklisp directory is evidence, not scratch space:
# leave it untouched rather than trying to repair or replace it automatically.
partial_quicklisp=$test_root/partial-quicklisp
mkdir -p -- "$partial_quicklisp"
printf 'keep this partial install\n' > "$partial_quicklisp/marker"
if PATH="$fake_bin:$PATH" \
   XDG_STATE_HOME="$test_root/partial-state" \
   CL_ART_BIN_DIR="$test_root/partial-bin" \
   CL_ART_QUICKLISP_HOME="$partial_quicklisp" \
   CL_ART_QUICKLISP_INSTALLER="$installer" \
   CL_ART_QUICKLISP_INSTALLER_SHA256="$installer_sum" \
   CL_ART_SBCL="$fake_bin/sbcl" \
   CL_ART_BOOTSTRAP_TESTING=1 \
   CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
   CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
   CL_ART_FAKE_INSTALL_SETUP=1 \
     bash "$repo_root/macos/bootstrap" --adopt-only --no-install-art; then
  printf 'bootstrap unexpectedly replaced a partial Quicklisp install\n' >&2
  exit 1
fi
grep -Fqx -- 'keep this partial install' "$partial_quicklisp/marker"
[[ ! -e $partial_quicklisp/setup.lisp ]]

# Never relinquish guix-sync ownership if one of cl-art's formulae is absent.
missing_root=$test_root/missing-state
mkdir -p -- "$missing_root/guix-sync"
missing_state=$missing_root/guix-sync/brew-managed
printf '%s\n' sdl2_ttf tree > "$missing_state"
cp -p -- "$missing_state" "$test_root/missing.original"
if PATH="$fake_bin:$PATH" \
   XDG_STATE_HOME="$missing_root" \
   CL_ART_BIN_DIR="$test_root/missing-bin" \
   CL_ART_QUICKLISP_HOME="$quicklisp_home" \
   CL_ART_SBCL="$fake_bin/sbcl" \
   CL_ART_BOOTSTRAP_TESTING=1 \
   CL_ART_FAKE_BREW_LOG="$fake_brew_log" \
   CL_ART_FAKE_SBCL_LOG="$fake_sbcl_log" \
   CL_ART_FAKE_MISSING=sdl2_ttf \
     bash "$repo_root/macos/bootstrap" --adopt-only; then
  printf 'bootstrap unexpectedly adopted a missing formula\n' >&2
  exit 1
fi
cmp -s -- "$test_root/missing.original" "$missing_state"
[[ ! -e ${missing_state}.before-cl-art ]]

for system in :dexador :shasht :quri :sdl2 :sdl2-image :sdl2-ttf; do
  grep -Fq -- "$system" "$repo_root/macos/quicklisp-systems.lisp"
done
for formula in sbcl sdl2-compat sdl2_image sdl2_ttf; do
  grep -Fqx -- "brew \"$formula\"" "$repo_root/macos/Brewfile"
done

# When a real SBCL is available, load the driver against a local Quicklisp
# facade.  QUICKLOAD is a no-op, so this is a syntax/dispatch test with no
# possible network access.
real_sbcl=$(command -v sbcl || true)
if [[ -n $real_sbcl ]]; then
  CL_ART_QUICKLISP_SETUP="$repo_root/tests/fixtures/quicklisp/setup.lisp" \
  CL_ART_QUICKLISP_MODE=preload \
    "$real_sbcl" --noinform --non-interactive \
      --load "$repo_root/macos/quicklisp-systems.lisp" --quit
fi

printf 'macOS bootstrap tests passed\n'
