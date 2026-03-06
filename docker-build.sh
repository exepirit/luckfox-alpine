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

IMAGE_ROOTFS="alpine-rootfs-builder"
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
    
    ensure_image "${IMAGE_ROOTFS}" "Dockerfile"
    
    mkdir -p "${PACKAGES_OUTPUT}"
    
    docker run --rm -t \
	--user builder \
	-v "abuild:/home/builder/.abuild" \
	-v "${SCRIPT_DIR}:/home/builder/sources" \
        -v "${PACKAGES_OUTPUT}:/home/builder/packages" \
        -w /home/builder/sources \
	-e "REPODEST=/home/builder/packages" \
        "${IMAGE_ROOTFS}" \
	python3 ./scripts/mkpackages.py \
            --branch mesh \
            --output-dir /home/builder/packages \
            --packages-dir /home/builder/sources/packages
    
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
            build_packages
            build_rootfs
            build_system
            echo ""
            echo "Build complete!"
            echo "Output: ${OUTPUT_DIR}/${DEVICE}-sysupgrade.img"
            ;;
    esac
}

main
