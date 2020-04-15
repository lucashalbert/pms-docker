#!/bin/bash

plex_ver=${plex_ver:-$(curl -s -L https://plex.tv/api/downloads/1.json?channel=plexpass | grep -Po '"version":.*?[^\\]",' | head -1 | cut -d'"' -f4)}
build_date=${build_date:-$(date +"%Y%m%dT%H%M%S")}

for docker_arch in amd64 arm32v7 arm64v8; do
    case ${docker_arch} in
        amd64   ) qemu_arch="x86_64"  image_arch="amd64" s6_arch="amd64"   plex_arch="amd64"   ;;
        arm32v7 ) qemu_arch="arm"     image_arch="arm"   s6_arch="arm"     plex_arch="armhf"   ;;
        arm64v8 ) qemu_arch="aarch64" image_arch="arm64" s6_arch="aarch64" plex_arch="arm64"   ;;
    esac
    cp Dockerfile.cross Dockerfile.${docker_arch}
    sed -i "s|__BASEIMAGE_ARCH__|${docker_arch}|g" Dockerfile.${docker_arch}
    sed -i "s|__BUILD_DATE__|${build_date}|g" Dockerfile.${docker_arch}
    sed -i "s|__QEMU_ARCH__|${qemu_arch}|g" Dockerfile.${docker_arch}
    sed -i "s|__S6_ARCH__|${s6_arch}|g" Dockerfile.${docker_arch}
    sed -i "s|__PLEX_VER__|${plex_ver}|g" Dockerfile.${docker_arch}
    sed -i "s|__PLEX_ARCH__|${plex_arch}|g" Dockerfile.${docker_arch}
    if [ ${docker_arch} == 'amd64' ]; then
        sed -i "/__CROSS__/d" Dockerfile.${docker_arch}
        cp Dockerfile.${docker_arch} Dockerfile
    else
        sed -i "s/__CROSS__//g" Dockerfile.${docker_arch}
    fi

   # Check for qemu static bins
    if [[ ! -f qemu-${qemu_arch}-static ]]; then
        echo "Downloading the qemu static binaries for ${docker_arch}"
        wget -q -N https://github.com/multiarch/qemu-user-static/releases/download/v4.0.0-4/x86_64_qemu-${qemu_arch}-static.tar.gz
        tar -xvf x86_64_qemu-${qemu_arch}-static.tar.gz
        rm x86_64_qemu-${qemu_arch}-static.tar.gz
    fi

    # Build
    if [ "$EUID" -ne 0 ]; then
	# Build container
        sudo docker build -f Dockerfile.${docker_arch} -t lucashalbert/pms-docker:${docker_arch}-${plex_ver} .
        sudo docker push lucashalbert/pms-docker:${docker_arch}-${plex_ver}

    else
	# Build container
        docker build -f Dockerfile.${docker_arch} -t lucashalbert/pms-docker:${docker_arch}-${plex_ver} .
        docker push lucashalbert/pms-docker:${docker_arch}-${plex_ver}

        # Create and annotate arch/ver docker manifest
        DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create lucashalbert/pms-docker:${docker_arch}-${plex_ver} lucashalbert/pms-docker:${docker_arch}-${plex_ver}
        DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate lucashalbert/pms-docker:${docker_arch}-${plex_ver} lucashalbert/pms-docker:${docker_arch}-${plex_ver} --os linux --arch ${image_arch}
        DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push lucashalbert/pms-docker:${docker_arch}-${plex_ver}

    fi
done



# Create version specific docker manifest
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create lucashalbert/pms-docker:${plex_ver} lucashalbert/pms-docker:amd64-${plex_ver} lucashalbert/pms-docker:arm32v7-${plex_ver} lucashalbert/pms-docker:arm64v8-${plex_ver}

# Create latest docker manifest
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest create lucashalbert/pms-docker:latest lucashalbert/pms-docker:amd64-${plex_ver} lucashalbert/pms-docker:arm32v7-${plex_ver} lucashalbert/pms-docker:arm64v8-${plex_ver}

for docker_arch in amd64 arm32v7 arm64v8; do
    case ${docker_arch} in
        amd64   ) image_arch="amd64" ;;
        arm32v7 ) image_arch="arm"   ;;
        arm64v8 ) image_arch="arm64" ;;    
    esac

    # Annotate version specific docker manifest
    DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate lucashalbert/pms-docker:${plex_ver} lucashalbert/pms-docker:${docker_arch}-${plex_ver} --os linux --arch ${image_arch}

    # Annotate latest docker manifest
    DOCKER_CLI_EXPERIMENTAL=enabled docker manifest annotate lucashalbert/pms-docker:latest lucashalbert/pms-docker:${docker_arch}-${plex_ver} --os linux --arch ${image_arch}
done

# Push version specific docker manifest
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push lucashalbert/pms-docker:${plex_ver}

# Push latest docker manifest
DOCKER_CLI_EXPERIMENTAL=enabled docker manifest push lucashalbert/pms-docker:latest
