#!/usr/bin/env bats
# Tests for install.sh
#
# Strategy: all tests run the script with a restricted PATH that only contains
# $MOCK_BIN plus essential utilities (mktemp, rm, mkdir, awk, tail).  This
# means a command is "absent" from the perspective of the script if and only
# if there is no mock for it in $MOCK_BIN.
#
# shellcheck disable=SC2016
# Single-quoted multi-line strings passed to _mock() intentionally contain
# literal $1, $@, etc. that must NOT be expanded in the test file — they are
# the body of the mock script that will be written to disk and executed later.

SCRIPT="$BATS_TEST_DIRNAME/../install.sh"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal valid gzip-compressed tarball containing a "copilot" binary.
_create_fake_tarball() {
  local dest="$1"
  local tmp
  tmp="$(mktemp -d)"
  printf '#!/bin/sh\necho copilot\n' > "$tmp/copilot"
  /usr/bin/chmod +x "$tmp/copilot"
  (cd "$tmp" && /usr/bin/tar czf "$dest" copilot)
  /usr/bin/rm -rf "$tmp"
}

# Write an executable mock script to $MOCK_BIN/<name>.
# Always removes any pre-existing file or symlink first so that overwriting
# a symlink (e.g. one pointing at a real system binary) never fails due to
# write-protected targets.
_mock() {
  local name="$1"; shift
  /usr/bin/rm -f "$MOCK_BIN/$name"
  printf '%s\n' "$@" > "$MOCK_BIN/$name"
  /usr/bin/chmod +x "$MOCK_BIN/$name"
}

# Run install.sh with a clean, restricted environment that only exposes the
# mock binaries in $MOCK_BIN.  Extra VAR=value pairs can be passed as
# positional arguments and are forwarded to env(1).
_run() {
  run env -i HOME="$FAKE_HOME" PATH="$MOCK_BIN" SHELL="/bin/sh" "$@" \
    "$MOCK_BIN/bash" "$SCRIPT"
}

# ---------------------------------------------------------------------------
# Per-test setup / teardown
# ---------------------------------------------------------------------------

setup() {
  MOCK_BIN="$(mktemp -d)"
  FAKE_HOME="$(mktemp -d)"
  FAKE_TARBALL="$MOCK_BIN/fake_copilot.tar.gz"

  # Build the fake tarball before PATH is restricted.
  _create_fake_tarball "$FAKE_TARBALL"

  # Symlink essential system utilities that the script relies on but that we
  # do not need to mock.  bash itself must be present so that
  # `env PATH="$MOCK_BIN" bash` can find the interpreter.
  for _tool in bash mktemp rm mkdir awk tail basename cp; do
    _tp="$(type -P "$_tool")"
    ln -sf "$_tp" "$MOCK_BIN/$_tool"
  done

  # ---- Default mock: uname (Linux x86_64) ----
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Linux" ;;
  -m) echo "x86_64" ;;
esac'

  # ---- Default mock: id (non-root) ----
  _mock id '#!/bin/sh
echo "1000"'

  # ---- Default mock: curl (copies fake tarball / creates checksum stub) ----
  _mock curl "#!/bin/sh
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-o\" ]; then
    case \"\$arg\" in
      *.tar.gz) cp \"\$FAKE_TARBALL\" \"\$arg\" ;;
      *)        printf 'fakechecksum  fake.tar.gz\n' > \"\$arg\" ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"

  # ---- Default mock: sha256sum (always succeeds) ----
  _mock sha256sum '#!/bin/sh
exit 0'

  # ---- Default mock: tar (validate + extract) ----
  _mock tar "#!/bin/sh
# Validation pass (-tzf): succeed immediately.
for a; do
  case \"\$a\" in -tzf) exit 0 ;; esac
done
# Extraction pass: find -C <dir> and place a fake copilot binary there.
prev=''
for a; do
  if [ \"\$prev\" = \"-C\" ]; then
    /usr/bin/mkdir -p \"\$a\"
    printf '#!/bin/sh\n' > \"\$a/copilot\"
    /usr/bin/chmod +x \"\$a/copilot\"
    exit 0
  fi
  prev=\"\$a\"
done
exit 0"

  # ---- Default mock: chmod (delegates to real chmod) ----
  _mock chmod '#!/bin/sh
/usr/bin/chmod "$@"'

  # ---- Default mock: copilot (present in PATH → no PATH-notice block) ----
  _mock copilot '#!/bin/sh
exit 0'

  # wget and git are intentionally absent unless a test explicitly adds them.
}

teardown() {
  /usr/bin/rm -rf "$MOCK_BIN"
  /usr/bin/rm -rf "$FAKE_HOME"
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

@test "detects Linux platform" {
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*linux"
}

@test "detects macOS platform" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Darwin" ;;
  -m) echo "x86_64" ;;
esac'
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*darwin"
}

@test "detects Windows via winget and exits successfully" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "MSYS_NT" ;;
  -m) echo "x86_64" ;;
esac'
  _mock winget '#!/bin/sh
echo "winget install GitHub.Copilot"
exit 0'
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Windows detected"
}

@test "errors on unrecognised platform when winget is absent" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "FreeBSD" ;;
  -m) echo "x86_64" ;;
esac'
  # winget mock is not created, so it is absent from the restricted PATH.
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "winget not found"
}

# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------

@test "detects x86_64 architecture" {
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*x64"
}

@test "detects amd64 architecture alias" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Linux" ;;
  -m) echo "amd64" ;;
esac'
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*x64"
}

@test "detects aarch64 architecture" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Linux" ;;
  -m) echo "aarch64" ;;
esac'
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*arm64"
}

@test "detects arm64 architecture alias" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Linux" ;;
  -m) echo "arm64" ;;
esac'
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Downloading from:.*arm64"
}

@test "errors on unsupported architecture" {
  _mock uname '#!/bin/sh
case "$1" in
  -s) echo "Linux" ;;
  -m) echo "mips" ;;
esac'
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unsupported architecture"
}

# ---------------------------------------------------------------------------
# VERSION / download URL construction
# ---------------------------------------------------------------------------

@test "uses latest URL when VERSION is unset" {
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "releases/latest/download"
}

@test "uses latest URL when VERSION=latest" {
  _run VERSION=latest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "releases/latest/download"
}

@test "uses version-specific URL when VERSION is set without v prefix" {
  _run VERSION=1.2.3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "releases/download/v1.2.3"
}

@test "uses version-specific URL when VERSION is set with v prefix" {
  _run VERSION=v1.2.3
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "releases/download/v1.2.3"
}

@test "prerelease errors when git is absent" {
  # git is not mocked in setup, so it is absent from the restricted PATH.
  _run VERSION=prerelease
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "git is required"
}

@test "prerelease uses git ls-remote to determine version" {
  _mock git '#!/bin/sh
echo "abc123	refs/tags/v9.8.7"'
  _run VERSION=prerelease
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "releases/download/v9.8.7"
}

@test "prerelease errors when git ls-remote returns no tags" {
  _mock git '#!/bin/sh
echo ""'
  _run VERSION=prerelease
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Could not determine prerelease version"
}

# ---------------------------------------------------------------------------
# Authentication (GITHUB_TOKEN)
# ---------------------------------------------------------------------------

@test "includes Authorization header when GITHUB_TOKEN is set" {
  _mock curl "#!/bin/sh
echo \"curl args: \$*\" >> '$MOCK_BIN/curl_args.log'
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-o\" ]; then
    case \"\$arg\" in
      *.tar.gz) cp \"\$FAKE_TARBALL\" \"\$arg\" ;;
      *)        printf 'fake\n' > \"\$arg\" ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"
  _run GITHUB_TOKEN=mytoken
  [ "$status" -eq 0 ]
  grep -q "Authorization: token mytoken" "$MOCK_BIN/curl_args.log"
}

@test "does not include Authorization header when GITHUB_TOKEN is absent" {
  _mock curl "#!/bin/sh
echo \"curl args: \$*\" >> '$MOCK_BIN/curl_args.log'
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-o\" ]; then
    case \"\$arg\" in
      *.tar.gz) cp \"\$FAKE_TARBALL\" \"\$arg\" ;;
      *)        printf 'fake\n' > \"\$arg\" ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"
  _run
  [ "$status" -eq 0 ]
  run grep -q "Authorization" "$MOCK_BIN/curl_args.log"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Download tool selection
# ---------------------------------------------------------------------------

@test "uses curl when available" {
  _mock curl "#!/bin/sh
echo 'curl called' >> '$MOCK_BIN/download.log'
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-o\" ]; then
    case \"\$arg\" in
      *.tar.gz) cp \"\$FAKE_TARBALL\" \"\$arg\" ;;
      *)        printf 'fake\n' > \"\$arg\" ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"
  _run
  [ "$status" -eq 0 ]
  grep -q "curl called" "$MOCK_BIN/download.log"
}

@test "falls back to wget when curl is absent" {
  # Remove curl mock so it is absent from the restricted PATH.
  rm "$MOCK_BIN/curl"
  _mock wget "#!/bin/sh
echo 'wget called' >> '$MOCK_BIN/download.log'
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-qO\" ]; then
    case \"\$arg\" in
      *.tar.gz) cp \"\$FAKE_TARBALL\" \"\$arg\" ;;
      *)        printf 'fake\n' > \"\$arg\" ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"
  _run
  [ "$status" -eq 0 ]
  grep -q "wget called" "$MOCK_BIN/download.log"
}

@test "errors when neither curl nor wget is available" {
  # Remove curl mock; wget is not mocked in setup.
  rm "$MOCK_BIN/curl"
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Neither curl nor wget"
}

# ---------------------------------------------------------------------------
# Checksum validation
# ---------------------------------------------------------------------------

@test "validates checksum with sha256sum when available" {
  _mock sha256sum "#!/bin/sh
echo 'sha256sum called' >> '$MOCK_BIN/checksum.log'
exit 0"
  _run
  [ "$status" -eq 0 ]
  grep -q "sha256sum called" "$MOCK_BIN/checksum.log"
  echo "$output" | grep -q "Checksum validated"
}

@test "falls back to shasum when sha256sum is absent" {
  rm "$MOCK_BIN/sha256sum"
  _mock shasum "#!/bin/sh
echo 'shasum called' >> '$MOCK_BIN/checksum.log'
exit 0"
  _run
  [ "$status" -eq 0 ]
  grep -q "shasum called" "$MOCK_BIN/checksum.log"
  echo "$output" | grep -q "Checksum validated"
}

@test "warns but continues when neither sha256sum nor shasum is available" {
  rm "$MOCK_BIN/sha256sum"
  # shasum is not mocked in setup.
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "skipping checksum validation"
}

@test "errors when sha256sum reports a checksum mismatch" {
  _mock sha256sum '#!/bin/sh
exit 1'
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Checksum validation failed"
}

@test "errors when shasum reports a checksum mismatch" {
  rm "$MOCK_BIN/sha256sum"
  _mock shasum '#!/bin/sh
exit 1'
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Checksum validation failed"
}

@test "skips checksum validation when checksums file cannot be downloaded" {
  # curl succeeds for tarball but fails for checksums, so CHECKSUMS_AVAILABLE
  # stays false and sha256sum should never be called.
  _mock curl "#!/bin/sh
FAKE_TARBALL='$FAKE_TARBALL'
prev=''
for arg; do
  if [ \"\$prev\" = \"-o\" ]; then
    case \"\$arg\" in
      *.tar.gz)
        cp \"\$FAKE_TARBALL\" \"\$arg\"
        exit 0
        ;;
      *)
        # Checksums download fails; CHECKSUMS_AVAILABLE will stay false.
        exit 1
        ;;
    esac
  fi
  prev=\"\$arg\"
done
exit 0"
  _mock sha256sum "#!/bin/sh
echo 'sha256sum called' >> '$MOCK_BIN/checksum.log'
exit 0"
  _run
  [ "$status" -eq 0 ]
  # Assert sha256sum was NOT called: checksum.log must be absent or contain no match.
  run grep -q "sha256sum called" "$MOCK_BIN/checksum.log"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Tarball validation
# ---------------------------------------------------------------------------

@test "errors when the downloaded file is not a valid tarball" {
  _mock tar '#!/bin/sh
for a; do
  case "$a" in -tzf) exit 1 ;; esac
done
exit 0'
  _run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "not a valid tarball"
}

# ---------------------------------------------------------------------------
# Install directory selection
# ---------------------------------------------------------------------------

@test "installs to custom PREFIX/bin when PREFIX is set" {
  _run PREFIX="$FAKE_HOME/custom"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$FAKE_HOME/custom/bin"
}

@test "installs to /usr/local/bin when running as root" {
  # When id returns 0 (root) the default PREFIX is /usr/local.  We pass an
  # explicit PREFIX so the test does not try to write to the real /usr/local.
  _mock id '#!/bin/sh
echo "0"'
  _run PREFIX="$FAKE_HOME/root_prefix"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$FAKE_HOME/root_prefix/bin"
}

@test "installs to \$HOME/.local/bin when running as non-root" {
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$FAKE_HOME/.local/bin"
}

@test "errors when install directory cannot be created" {
  local blocker="$FAKE_HOME/blocked"
  touch "$blocker"
  # Replace mkdir with a script that fails for paths containing 'blocked'.
  _mock mkdir "#!/bin/sh
for a; do
  if echo \"\$a\" | grep -q 'blocked'; then
    echo 'mkdir: cannot create' >&2
    exit 1
  fi
done
/usr/bin/mkdir \"\$@\""
  _run PREFIX="$blocker"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Could not create directory"
}

# ---------------------------------------------------------------------------
# Existing binary replacement
# ---------------------------------------------------------------------------

@test "prints notice when replacing an existing copilot binary" {
  local install_dir="$FAKE_HOME/.local/bin"
  /usr/bin/mkdir -p "$install_dir"
  touch "$install_dir/copilot"
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Replacing copilot binary"
}

# ---------------------------------------------------------------------------
# PATH detection and shell rc suggestion
# ---------------------------------------------------------------------------

@test "prints PATH notice when copilot is not in PATH after install" {
  # Remove copilot mock so command -v copilot fails after installation.
  # The script then tries to read from /dev/tty; wrap with timeout so the
  # test does not hang in interactive terminal environments.
  /usr/bin/rm "$MOCK_BIN/copilot"
  run timeout 3 env -i HOME="$FAKE_HOME" PATH="$MOCK_BIN" SHELL="/bin/sh" \
    "$MOCK_BIN/bash" "$SCRIPT"
  # Accept exit 0 (success) or 124 (killed by timeout after printing the notice).
  [ "$status" -eq 0 ] || [ "$status" -eq 124 ]
  echo "$output" | grep -q "not in your PATH"
}

@test "prints no PATH notice when copilot is already in PATH" {
  # copilot mock is present in MOCK_BIN (added in setup).
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Run 'copilot help'"
  run grep -q "not in your PATH" <<< "$output"
  [ "$status" -ne 0 ]
}

@test "installation success message is displayed" {
  _run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "GitHub Copilot CLI installed"
}
