#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
PACKAGES_DIR="${SCRIPT_DIR}/packages"
PACKAGES_OUTPUT="${OUTPUT_DIR}/packages"
DEVICE="pico-mini-flash"
TARGET="all"
ARCH="armv7"
UID_GID="$(id -u):$(id -g)"

IMAGE_ROOTFS="luckfox-rootfs-builder"
IMAGE_SYSTEM="luckfox-system-builder"

usage() {
    echo "Usage: $0 [OPTIONS] [TARGET]"
    echo ""
    echo "Targets:"
    echo "  rootfs    Build only rootfs"
    echo "  system    Build only system image (requires existing rootfs)"
    echo "  packages  Build all packages from packages/mesh"
    echo "  all       Build both rootfs and system (default)"
    echo ""
    echo "Options:"
    echo "  -d, --device DEVICE   Device name (default: pico-mini-flash)"
    echo "  -a, --arch ARCH       Target architecture (default: armv7)"
    echo "  -h, --help            Show this help"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--device)
            DEVICE="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        rootfs|system|packages|all)
            TARGET="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

ensure_image() {
    local name="$1"
    local dockerfile="$2"
    
    if ! docker image inspect "$name" >/dev/null 2>&1; then
        echo "==> Building Docker image: $name"
        docker build -t "$name" -f "$dockerfile" "${SCRIPT_DIR}"
    fi
}

build_packages() {
    echo "==> Building packages..."
    
    ensure_image "${IMAGE_ROOTFS}" "Dockerfile.rootfs"
    
    mkdir -p "${PACKAGES_OUTPUT}"
    
    docker run --rm \
        -v "${PACKAGES_DIR}:/packages:ro" \
        -v "${SCRIPT_DIR}/scripts:/scripts:ro" \
        -v "${PACKAGES_OUTPUT}:/output" \
        -w /output \
        "${IMAGE_ROOTFS}" \
        sh -c '
            chown -R builder:abuild /output
            
            PACKAGER_PRIVKEY="/output/abuild.rsa"
            if [ ! -f "$PACKAGER_PRIVKEY" ]; then
                su builder -c "abuild-keygen -a -n"
                cp "$HOME/builder/.abuild/"*.rsa.pub "$PACKAGER_PRIVKEY.pub" 2>/dev/null || \
                    cp /home/builder/.abuild/*.rsa.pub "$PACKAGER_PRIVKEY.pub"
                cp /home/builder/.abuild/*.rsa "$PACKAGER_PRIVKEY"
                chmod 600 "$PACKAGER_PRIVKEY"
                chmod 644 "$PACKAGER_PRIVKEY.pub"
            fi
            
            for pubkey in /home/builder/.abuild/*.rsa.pub; do
                [ -f "$pubkey" ] && cp "$pubkey" /etc/apk/keys/
            done
            
            export PACKAGER_PRIVKEY="$PACKAGER_PRIVKEY"
            export REPODEST="/output"
            
            for pkgdir in /packages/mesh/*/; do
                pkgname=$(basename "$pkgdir")
                echo "Building: $pkgname"
                
                mkdir -p "/tmp/build/$pkgname"
                cp -r "$pkgdir"/* "/tmp/build/$pkgname/"
                chown -R builder:abuild "/tmp/build/$pkgname"
                cd "/tmp/build/$pkgname"
                
                su builder -c "abuild -r"
            done
            
            chown -R '"${UID_GID}"' /output
        '
    
    echo "Packages built in: ${PACKAGES_OUTPUT}"
}

build_rootfs() {
    echo "==> Building rootfs..."
    
    ensure_image "${IMAGE_ROOTFS}" "Dockerfile.rootfs"
    
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "${SCRIPT_DIR}:/src:ro" \
        -v "${OUTPUT_DIR}:/output" \
        -w /src \
        "${IMAGE_ROOTFS}" \
        sh -c '
            ./scripts/mkimage.sh \
                --arch '"${ARCH}"' \
                --outdir /output \
                --profile luckfox \
                --repository https://dl-cdn.alpinelinux.org/alpine/v3.23/main
        '
    
    ROOTFS_FILE=$(find "${OUTPUT_DIR}" -name "alpine-luckfox-*-*.tar.gz" -print -quit)
    echo "Rootfs built: ${ROOTFS_FILE}"
    echo "${ROOTFS_FILE}"
}

build_system() {
    local rootfs_file="$1"
    
    echo "==> Building system image for ${DEVICE}..."
    
    ensure_image "${IMAGE_SYSTEM}" "Dockerfile.system"
    
    docker run --rm \
        -v "${SCRIPT_DIR}:/src" \
        -v "${OUTPUT_DIR}:/output" \
        -w /src \
        "${IMAGE_SYSTEM}" \
        bash -c '
            if [ ! -d "sdk/.git" ]; then
                git submodule update --init --recursive
            fi
            
            ./system.sh -f "'"$rootfs_file"'" -d "'"$DEVICE"'"
            
            chown -R '"${UID_GID}"' /output
        '
    
    echo "System image built: ${OUTPUT_DIR}/${DEVICE}-sysupgrade.img"
}

find_rootfs() {
    find "${OUTPUT_DIR}" -name "alpine-luckfox-*-*.tar.gz" -print -quit 2>/dev/null || true
}

main() {
    mkdir -p "${OUTPUT_DIR}"
    
    case "${TARGET}" in
        packages)
            build_packages
            echo ""
            echo "Packages build complete!"
            ;;
        rootfs)
            build_rootfs | tail -1
            echo ""
            echo "Rootfs build complete!"
            ;;
        system)
            ROOTFS_FILE=$(find_rootfs)
            if [ -z "${ROOTFS_FILE}" ] || [ ! -f "${ROOTFS_FILE}" ]; then
                echo "Error: No rootfs found. Build rootfs first: $0 rootfs"
                exit 1
            fi
            build_system "${ROOTFS_FILE}"
            echo ""
            echo "System build complete!"
            echo "Output: ${OUTPUT_DIR}/${DEVICE}-sysupgrade.img"
            ;;
        all)
            ROOTFS_FILE=$(build_rootfs | tail -1)
            if [ -z "${ROOTFS_FILE}" ] || [ ! -f "${ROOTFS_FILE}" ]; then
                echo "Error: Failed to build rootfs"
                exit 1
            fi
            build_system "${ROOTFS_FILE}"
            echo ""
            echo "Build complete!"
            echo "Output: ${OUTPUT_DIR}/${DEVICE}-sysupgrade.img"
            ;;
    esac
}

main