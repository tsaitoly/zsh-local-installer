#!/bin/bash

# Zsh Manual Installation Script for Ubuntu
# Installs ncurses, zsh from source, sets as default shell, and installs oh-my-zsh

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NCURSES_VERSION="6.4"
ZSH_VERSION="5.9"
INSTALL_PREFIX="/usr/local"  # Will be updated in check_privileges if not root
BUILD_DIR="/tmp/zsh_build"
CURRENT_USER=$(whoami)
IS_ROOT=false

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root or with sudo
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Installing to system directories."
        IS_ROOT=true
    else
        print_status "Running as regular user. Installing to user directories."
        IS_ROOT=false
        # Update install prefix for user installation
        INSTALL_PREFIX="$HOME/.local"
    fi
}

# Function to check Ubuntu version
check_ubuntu() {
    if ! grep -q "Ubuntu" /etc/os-release; then
        print_warning "This script is designed for Ubuntu. Continuing anyway..."
    fi
}

# Function to install build dependencies
install_build_deps() {
    print_status "Checking for build dependencies..."

    # Check if essential tools are available
    local missing_tools=()

    for tool in gcc make wget curl git pkg-config; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        print_error "Missing required build tools: ${missing_tools[*]}"
        print_error "Please install these tools first (assuming they're available without apt-get)"
        exit 1
    fi

    print_success "All required build dependencies are available"
}

# Function to setup build directory
setup_build_dir() {
    print_status "Setting up build directory..."

    # Use user-specific temp directory if not root
    if [[ "$IS_ROOT" == false ]]; then
        BUILD_DIR="$HOME/tmp/zsh_build"
    fi

    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    print_success "Build directory created: $BUILD_DIR"
}

# Function to build and install ncurses
install_ncurses() {
    print_status "Downloading and building ncurses $NCURSES_VERSION..."

    cd "$BUILD_DIR"

    # Create install directory if not root
    if [[ "$IS_ROOT" == false ]]; then
        mkdir -p "$INSTALL_PREFIX"/{bin,lib,include,share}
    fi

    # Download ncurses
    wget -q "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
    tar -xzf "ncurses-${NCURSES_VERSION}.tar.gz"
    cd "ncurses-${NCURSES_VERSION}"

    # Configure ncurses
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --with-shared \
        --with-normal \
        --with-debug \
        --with-cxx-shared \
        --enable-widec \
        --enable-pc-files \
        --with-pkg-config-libdir="$INSTALL_PREFIX/lib/pkgconfig"

    # Build and install
    make -j"$(nproc)"
    make install

    # Update library cache (only if root)
    if [[ "$IS_ROOT" == true ]]; then
        echo "$INSTALL_PREFIX/lib" > /etc/ld.so.conf.d/ncurses.conf
        ldconfig
    else
        # For user installation, update LD_LIBRARY_PATH
        export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"
    fi

    print_success "ncurses $NCURSES_VERSION installed successfully"
}

# Function to build and install zsh
install_zsh() {
    print_status "Downloading and building zsh $ZSH_VERSION..."

    cd "$BUILD_DIR"

    # Download zsh
    wget -q "https://www.zsh.org/pub/zsh-${ZSH_VERSION}.tar.xz"
    tar -xf "zsh-${ZSH_VERSION}.tar.xz"
    cd "zsh-${ZSH_VERSION}"

    # Set environment variables for ncurses
    export CPPFLAGS="-I$INSTALL_PREFIX/include -I$INSTALL_PREFIX/include/ncursesw"
    export LDFLAGS="-L$INSTALL_PREFIX/lib"
    export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
    export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"

    # Configure zsh
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --enable-multibyte \
        --enable-function-subdirs \
        --enable-fndir="$INSTALL_PREFIX/share/zsh/functions" \
        --enable-scriptdir="$INSTALL_PREFIX/share/zsh/scripts" \
        --with-tcsetpgrp \
        --enable-pcre \
        --enable-cap \
        --enable-zsh-secure-free

    # Build and install
    make -j"$(nproc)"
    make install

    print_success "zsh $ZSH_VERSION installed successfully"
}



# Function to install oh-my-zsh
install_oh_my_zsh() {
    print_status "Installing oh-my-zsh..."

    # Determine target user and home directory
    if [[ "$IS_ROOT" == true && -n "$SUDO_USER" ]]; then
        USER_HOME=$(eval echo "~$SUDO_USER")
        TARGET_USER="$SUDO_USER"
    else
        USER_HOME="$HOME"
        TARGET_USER="$CURRENT_USER"
    fi

    # Ensure zsh is in PATH for oh-my-zsh installer
    export PATH="$INSTALL_PREFIX/bin:$PATH"

    # Download and install oh-my-zsh
    if [[ "$IS_ROOT" == true && "$TARGET_USER" != "root" ]]; then
        sudo -u "$TARGET_USER" env PATH="$INSTALL_PREFIX/bin:$PATH" sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # Create a basic .zshrc if it doesn't exist or backup existing one
    ZSHRC_PATH="$USER_HOME/.zshrc"

    if [[ -f "$ZSHRC_PATH" ]]; then
        if [[ "$IS_ROOT" == true && "$TARGET_USER" != "root" ]]; then
            sudo -u "$TARGET_USER" cp "$ZSHRC_PATH" "$ZSHRC_PATH.backup.$(date +%Y%m%d_%H%M%S)"
        else
            cp "$ZSHRC_PATH" "$ZSHRC_PATH.backup.$(date +%Y%m%d_%H%M%S)"
        fi
    fi

    # Create a basic .zshrc configuration
    cat > "$ZSHRC_PATH" << EOF
# Path to your oh-my-zsh installation.
export ZSH="\$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="robbyrussell"

# Which plugins would you like to load?
plugins=(git sudo history-substring-search colored-man-pages)

source \$ZSH/oh-my-zsh.sh

# User configuration
export PATH="$INSTALL_PREFIX/bin:\$PATH"
export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
export EDITOR='nano'

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
EOF

    # Set proper ownership
    if [[ "$IS_ROOT" == true && "$TARGET_USER" != "root" ]]; then
        chown "$TARGET_USER:$(id -gn "$TARGET_USER")" "$ZSHRC_PATH"
    fi

    print_success "oh-my-zsh installed and configured for user: $TARGET_USER"
}

# Function to cleanup build directory
cleanup() {
    print_status "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"

    # Also cleanup the parent temp directory if it's user-specific
    if [[ "$IS_ROOT" == false && -d "$HOME/tmp" ]]; then
        # Only remove if it's empty after removing our build directory
        rmdir "$HOME/tmp" 2>/dev/null || true
    fi

    print_success "Cleanup completed"
}

# Function to display installation summary
display_summary() {
    print_success "=== Installation Summary ==="
    echo -e "${GREEN}✓${NC} ncurses $NCURSES_VERSION installed to $INSTALL_PREFIX"
    echo -e "${GREEN}✓${NC} zsh $ZSH_VERSION installed to $INSTALL_PREFIX/bin/zsh"
    echo -e "${GREEN}✓${NC} oh-my-zsh installed and configured"
    echo ""
    print_status "To start using zsh, run:"
    echo "  exec $INSTALL_PREFIX/bin/zsh"
    echo ""

    if [[ "$IS_ROOT" == false ]]; then
        print_warning "User installation notes:"
        echo "  - Make sure $INSTALL_PREFIX/bin is in your PATH"
        echo "  - Library path is set in .zshrc: $INSTALL_PREFIX/lib"
    else
        print_warning "Note: Make sure $INSTALL_PREFIX/bin is in your PATH"
    fi
}

# Main installation function
main() {
    print_status "Starting Zsh manual installation..."

    check_privileges
    check_ubuntu
    install_build_deps
    setup_build_dir
    install_ncurses
    install_zsh
    install_oh_my_zsh
    cleanup
    display_summary

    print_success "Zsh installation completed successfully!"
}

# Trap to cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
