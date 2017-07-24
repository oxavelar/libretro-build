#/bin/bash
#
# This script is used in order to build libretro-super
# retro in a portable Unix way.
#
# Requirements:
# sudo apt-get install linux-libc-dev mesa-common-dev libgl1-mesa-dev libxml2-dev libudev-dev libz-dev libpng-dev libavformat-dev libvulkan-dev libclang-dev
#


CURR_DIR=$(realpath ${0%/*})
LIBRETRO_REPO="https://github.com/libretro/libretro-super"
LIBRETRO_PATH="${CURR_DIR}/$(basename ${LIBRETRO_REPO})/"
OUT_DIR="${CURR_DIR}/retroarch/"
BUILD_THREADS=$(grep -c cores /proc/cpuinfo)

export LIBRETRO_DEVELOPER=0
export DEBUG=0
export CFLAGS="-O3 -ftree-vectorize -ftree-slp-vectorize -fvect-cost-model -ftree-partial-pre -frename-registers -fweb -fgcse -fgcse-sm -fgcse-las -fivopts -foptimize-register-move -fipa-cp-clone -fipa-pta -fmodulo-sched -fmodulo-sched-allow-regmoves -fomit-frame-pointer -flto=${BUILD_THREADS} -fuse-ld=gold -fuse-linker-plugin -pipe"
export CFLAGS="${CFLAGS} -fgraphite-identity -ftree-loop-linear -floop-interchange -floop-strip-mine -floop-block"
export CFLAGS="${CFLAGS} -march=broadwell -mtune=generic"
export CFLAGS="${CFLAGS}"
export CXXFLAGS="${CFLAGS}"
export ASFLAGS="${CFLAGS}"
export LDFLAGS="${LDFLAGS} -Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed -Wl,-flto"

export CC="gcc-7"
export CXX="g++-7"
export AS="as"
export AR="gcc-ar"
export LINK="ld.gold"
export STRIP="strip"

function prerequisites()
{
    # Make sure we have libretro super and get inside, fetch if first time
    cd ${CURR_DIR}
    git clone ${LIBRETRO_REPO} && $(${LIBRETRO_PATH};"${LIBRETRO_PATH}/libretro-fetch.sh")

    # Update the packages
    cd "${LIBRETRO_PATH}" && git gc --prune=now && git clean -dfx && git reset --hard && git pull
    cd ${LIBRETRO_PATH}/retroarch && git gc --prune=now && git clean -dfx && git reset --hard && git pull

    cd "${LIBRETRO_PATH}"
    rm -rf $(realpath "${OUT_DIR}")
    mkdir -p $(realpath "${OUT_DIR}")

    # Temporary tmp path
    mkdir -p "${OUT_DIR}/tmp"
}

function build_retroarch()
{
    # Build retroarch
    cd "${LIBRETRO_PATH}/retroarch"
    make -j${BUILD_THREADS} clean
    #./configure --help || exit 0
    ./configure --enable-sse --enable-opengl --enable-vulkan --disable-xvideo --disable-cg --disable-v4l2 --disable-al --disable-jack --disable-coreaudio --disable-roar --enable-libxml2 --disable-ffmpeg --disable-videoprocessor --disable-sdl2 --disable-sdl --disable-wayland --disable-kms --disable-cheevos --disable-imageviewer --disable-parport --disable-langextra --disable-update_assets --disable-dbus --disable-networking || exit -127
    time make -f Makefile -j${BUILD_THREADS} || exit -99
    make DESTDIR="${OUT_DIR}/tmp" install
    cd ..
}

function build_libretro_select()
{
    cores=(
            "snes9x"
            "mupen64plus"
            "dolphin"
            "mgba"
            "ppsspp"
            "nestopia"
            "mednafen_psx"
            "reicast"
            "mame"
            "fbalpha"
    )

    for elem in "${cores[@]}"
      do
        cd "${LIBRETRO_PATH}/libretro-${elem}"
        # Update and reset the core git repo
        git gc --prune=now && git clean -dfx && git reset --hard && git pull
        # Back on libretro super instructions which also copies the *.so
        # https://buildbot.libretro.com/docs/compilation/ubuntu/
        cd "${LIBRETRO_PATH}"
        "${LIBRETRO_PATH}/libretro-build.sh" ${elem} || continue
      done
      cd ..
}

function build_libretro_all()
{
    "${LIBRETRO_PATH}/libretro-fetch.sh"
    "${LIBRETRO_PATH}/libretro-build.sh"
}

function install_libretro()
{
    "${LIBRETRO_PATH}/libretro-install.sh" "${OUT_DIR}"

    # Organize our files in a portable structure
    mkdir -p "${OUT_DIR}/bin" "${OUT_DIR}/cores-info" "${OUT_DIR}/cores-info" "${OUT_DIR}/cores" "${OUT_DIR}/shaders" "${OUT_DIR}/lib" "${OUT_DIR}/autoconfig/" "${OUT_DIR}/downloads/" "${OUT_DIR}/system/" "${OUT_DIR}/screenshots/" "${OUT_DIR}/assets/" "${OUT_DIR}/overlays/" "${OUT_DIR}/saves/" "${OUT_DIR}/roms/" "${OUT_DIR}/remaps/" "${OUT_DIR}/database/" "${OUT_DIR}/thumbnails/" "${OUT_DIR}/playlists"
    cp -av "${OUT_DIR}/tmp/usr/local/bin/." "${OUT_DIR}/bin"
    cp -av "${OUT_DIR}/tmp/etc/." "${OUT_DIR}/config"
    cp -av "${OUT_DIR}/tmp/usr/local/share/retroarch/assets/." "${OUT_DIR}/assets"
    mv -vf "${OUT_DIR}/config/retroarch.cfg" "${OUT_DIR}/config/retroarch.cfg.bak"
    find "${OUT_DIR}" -name "*.info" -exec mv -vf \{\} "${OUT_DIR}/cores-info/" 2> /dev/null \;
    find "${OUT_DIR}" -name "*.so" -exec mv -vf \{\} "${OUT_DIR}/cores/" 2> /dev/null \;

    # Moving prebuilts
    cp -av "${LIBRETRO_PATH}/retroarch/media/shaders_cg" "${OUT_DIR}/shaders"
    cp -av "${LIBRETRO_PATH}/retroarch/media/autoconfig" "${OUT_DIR}/autoconfig/joypad"
    cp -av "${LIBRETRO_PATH}/retroarch/media/libretrodb/." "${OUT_DIR}/database"

    # Cleanup left-overs and any .git files for distribution
    rm -rf "${OUT_DIR}/tmp"
    ( find "${OUT_DIR}" -type d -name ".git" \
      && find . -name ".gitignore" \
      && find . -name ".gitmodules" ) | xargs rm -rf
}

function extras_libretro()
{
    # Convert shaders
    "${LIBRETRO_PATH}/retroarch/tools/cg2glsl.py" "${OUT_DIR}/shaders/shaders_cg" "${OUT_DIR}/shaders/shaders_glsl"
    
    # Strip out debug symbols from the shared libraries and main binary
    ${STRIP} --strip-debug --strip-unneeded --remove-section=.comment --remove-section=.note ${OUT_DIR}/cores/*.so
    ${STRIP} --strip-debug --strip-unneeded --remove-section=.comment --remove-section=.note ${OUT_DIR}/bin/retroarch

    # Zip for distribution
    zip -rq "${OUT_DIR}/retroarch-x86_64.zip" "${OUT_DIR}"
}


# The main sequence of steps now go here ...
prerequisites
build_retroarch
##build_libretro_all
build_libretro_select
install_libretro
extras_libretro
sync
exit 0

