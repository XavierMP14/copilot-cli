#!/usr/bin/env bash
set -e

# KRUMAQ-COPILOT CLI Installation Script
# Usage: curl -fsSL https://raw.githubusercontent.com/XavierMP14/copilot-cli/main/krumaq-install.sh | bash
#    or: wget -qO- https://raw.githubusercontent.com/XavierMP14/copilot-cli/main/krumaq-install.sh | bash
#
# Use | sudo bash to install system-wide to /usr/local/bin.
# Set PREFIX to override the install directory, e.g.:
#   PREFIX="$HOME/custom" bash krumaq-install.sh

echo "Installing KRUMAQ-COPILOT CLI..."

# ── Dependency checks ─────────────────────────────────────────────────────────
MISSING_DEPS=()
for dep in curl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    MISSING_DEPS+=("$dep")
  fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  echo "Error: The following required tools are missing: ${MISSING_DEPS[*]}" >&2
  echo ""
  echo "Install them with your package manager, for example:" >&2
  echo "  Ubuntu/Debian:  sudo apt install -y ${MISSING_DEPS[*]}" >&2
  echo "  macOS:          brew install ${MISSING_DEPS[*]}" >&2
  exit 1
fi

# ── Platform detection ────────────────────────────────────────────────────────
case "$(uname -s || echo "")" in
  Darwin*) PLATFORM="darwin" ;;
  Linux*)  PLATFORM="linux" ;;
  *)
    echo "Error: Unsupported platform. Only Linux and macOS are supported." >&2
    exit 1
    ;;
esac

# ── Install directory ─────────────────────────────────────────────────────────
if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
  PREFIX="${PREFIX:-/usr/local}"
else
  PREFIX="${PREFIX:-$HOME/.local}"
fi
INSTALL_DIR="$PREFIX/bin"

if ! mkdir -p "$INSTALL_DIR"; then
  echo "Error: Could not create $INSTALL_DIR. Try running with sudo or set PREFIX." >&2
  exit 1
fi

# ── Download the krumaq script ────────────────────────────────────────────────
SCRIPT_URL="${KRUMAQ_SCRIPT_URL:-https://raw.githubusercontent.com/XavierMP14/copilot-cli/main/krumaq}"
TMP_FILE="$(mktemp)"
trap 'rm -f -- "$TMP_FILE"' EXIT

echo "Downloading krumaq from: $SCRIPT_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$SCRIPT_URL" -o "$TMP_FILE"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$TMP_FILE" "$SCRIPT_URL"
else
  echo "Error: Neither curl nor wget found." >&2
  exit 1
fi

# Sanity-check: make sure we got a shell script, not an error page
if ! head -1 "$TMP_FILE" | grep -qE '^#!.*sh'; then
  echo "Error: Downloaded file does not look like a shell script. Check the URL." >&2
  exit 1
fi

# ── Install ───────────────────────────────────────────────────────────────────
if [ -f "$INSTALL_DIR/krumaq" ]; then
  echo "Notice: Replacing existing krumaq binary at $INSTALL_DIR/krumaq."
fi
cp "$TMP_FILE" "$INSTALL_DIR/krumaq"
chmod +x "$INSTALL_DIR/krumaq"
echo "✓ KRUMAQ-COPILOT CLI installed to $INSTALL_DIR/krumaq"

# ── Write default config if not present ───────────────────────────────────────
CONFIG_DIR="${HOME}/.config/krumaq"
CONFIG_FILE="${CONFIG_DIR}/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" <<'CONFIG'
# KRUMAQ-COPILOT configuration
# Source this file or add it to your shell profile to set defaults.
#
# Ollama host — change this if Ollama is running on a different machine
# or a non-default port.
export KRUMAQ_HOST="http://localhost:11434"
#
# Default model — run `krumaq --list` to see available models.
export KRUMAQ_MODEL="llama3.2"
CONFIG
  echo "✓ Default config written to $CONFIG_FILE"
  echo "  Edit it to point KRUMAQ_HOST at your Ollama server."
fi

# ── PATH notice ───────────────────────────────────────────────────────────────
if ! command -v krumaq >/dev/null 2>&1; then
  echo ""
  echo "Notice: $INSTALL_DIR is not in your PATH."

  CURRENT_SHELL="$(basename "${SHELL:-/bin/sh}")"
  case "$CURRENT_SHELL" in
    zsh)  RC_FILE="${ZDOTDIR:-$HOME}/.zprofile" ;;
    bash)
      if [ -f "$HOME/.bash_profile" ]; then
        RC_FILE="$HOME/.bash_profile"
      elif [ -f "$HOME/.bash_login" ]; then
        RC_FILE="$HOME/.bash_login"
      else
        RC_FILE="$HOME/.profile"
      fi
      ;;
    fish) RC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/krumaq.fish" ;;
    *)    RC_FILE="$HOME/.profile" ;;
  esac

  PATH_LINE="export PATH=\"$INSTALL_DIR:\$PATH\""
  if [ "$CURRENT_SHELL" = "fish" ]; then
    PATH_LINE="fish_add_path \"$INSTALL_DIR\""
  fi

  if [ -t 0 ] && [ -e /dev/tty ] && { read -r _ </dev/tty; } 2>/dev/null; then
    echo ""
    printf "Would you like to add %s to PATH in %s? [y/N] " "$INSTALL_DIR" "$RC_FILE"
    read -r REPLY </dev/tty 2>/dev/null || REPLY=""
    if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
      mkdir -p "$(dirname "$RC_FILE")"
      echo "$PATH_LINE" >> "$RC_FILE"
      echo "✓ Added PATH configuration to $RC_FILE"
      echo "  Restart your shell or run: source $RC_FILE"
    fi
  else
    echo "  Add this to $RC_FILE:"
    echo "    $PATH_LINE"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Installation complete!"
echo ""
echo "  Start the backend:  docker compose up -d   (see docker-compose.yml)"
echo "  Pull a model:       krumaq --pull llama3.2"
echo "  Chat:               krumaq"
echo "  One-shot query:     krumaq \"explain quantum computing in simple terms\""
echo ""
echo "  Configuration:      $CONFIG_FILE"
echo "  Full guide:         https://github.com/XavierMP14/copilot-cli/blob/main/KRUMAQ-COPILOT.md"
