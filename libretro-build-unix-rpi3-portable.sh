#/bin/bash
#
# This script is used in order to build libretro-super
# retro in a portable Unix way.
#
# Requirements:
# sudo apt-get install linux-libc-dev:armhf mesa-common-dev:armhf libxml2-dev:armhf libudev-dev:armhf libglu1-mesa-dev:armhf libgl1-mesa-dev:armhf libegl1-mesa-dev:armhf libgles2-mesa-dev libz-dev:armhf libpng-dev:armhf libavformat-dev:armhf
#
# Linaro Workarounds:
# ln -s /usr/include/GLES2/ /usr/include/arm-linux-gnueabihf/
# ln -s /usr/include/KHR/ /usr/include/arm-linux-gnueabihf/


CURR_DIR=$(realpath ${0%/*})
LIBRETRO_REPO="https://github.com/libretro/libretro-super"
LIBRETRO_PATH="${CURR_DIR}/$(basename ${LIBRETRO_REPO})/"
OUT_DIR="${CURR_DIR}/retroarch/"
BUILD_THREADS=$(grep -c cores /proc/cpuinfo)

export LIBRETRO_DEVELOPER=0
export DEBUG=0
export CFLAGS="-O3 -ftree-vectorize -ftree-slp-vectorize -fvect-cost-model -ftree-partial-pre -frename-registers -fweb -fgcse -fgcse-sm -fgcse-las -fivopts -foptimize-register-move -fipa-cp-clone -fipa-pta -fmodulo-sched -fmodulo-sched-allow-regmoves -fomit-frame-pointer"
export CFLAGS="${CFLAGS} -fgraphite-identity -ftree-loop-linear -floop-interchange -floop-strip-mine -floop-block"
export CFLAGS="${CFLAGS} -march=armv8-a+crc -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard -funsafe-math-optimizations -mvectorize-with-neon-quad"
export CFLAGS="${CFLAGS}"
export CXXFLAGS="${CFLAGS}"
export ASFLAGS="${CFLAGS}"
export LDFLAGS="${LDFLAGS} -Wl,-O1 -Wl,--hash-style=gnu -Wl,--as-needed"

export CROSS_COMPILE="/usr/bin/arm-linux-gnueabihf-"
export CC="${CROSS_COMPILE}gcc -L${CURR_DIR}/prebuilt/rpi3/ -I/usr/include/arm-linux-gnueabihf/"
export CXX="${CROSS_COMPILE}g++ -L${CURR_DIR}/prebuilt/rpi3/ -I/usr/include/arm-linux-gnueabihf/"
export AS="${CROSS_COMPILE}as"
export AR="${CROSS_COMPILE}ar"
export LINK="${CROSS_COMPILE}gold"
export STRIP="${CROSS_COMPILE}strip"

function prerequisites()
{
    # Make sure we have libretro super and get inside, fetch if first time
    cd ${CURR_DIR}
    git clone ${LIBRETRO_REPO} && $(${LIBRETRO_PATH};"${LIBRETRO_PATH}/libretro-fetch.sh")

    # Update the packages
    cd "${LIBRETRO_PATH}" && git gc && git clean -dfx && git reset --hard && git pull
    cd ${LIBRETRO_PATH}/retroarch && git gc && git clean -dfx && git reset --hard && git pull

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
    ./configure --enable-neon --enable-opengles --disable-vulkan --disable-xvideo --disable-cg --disable-v4l2 --disable-libxml2 --disable-ffmpeg --disable-sdl2 --disable-sdl --disable-wayland --disable-kms --disable-cheevos --disable-imageviewer --disable-parport --disable-langextra --disable-update_assets --disable-dbus --disable-miniupnpc || exit -127
    time make -f Makefile -j${BUILD_THREADS} || exit -99
    make DESTDIR="${OUT_DIR}/tmp" install
    cd ..
}

function build_libretro_select()
{
    cores=(
            "fbalpha"
            "snes9x2010"
            "mupen64plus"
            "mgba"
            "ppsspp/libretro"
            "nestopia/libretro"
            "mednafen_psx"
            "reicast"
            "mame2014"
            "glupen64"
    )

    for elem in "${cores[@]}"
      do
        cd "${LIBRETRO_PATH}/libretro-${elem}"
        # Update and reset the core
        git gc && git clean -dfx && git reset --hard && git pull
        make -j${BUILD_THREADS} clean && make platform="rpi" -j${BUILD_THREADS} || continue
        # Copy it over the build dir
        find . -name "*.so" -exec mv -vf \{\} "${OUT_DIR}/tmp/" 2> /dev/null \;
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
    mkdir -p "${OUT_DIR}/bin" "${OUT_DIR}/cores-info" "${OUT_DIR}/cores-info" "${OUT_DIR}/cores" "${OUT_DIR}/shaders" "${OUT_DIR}/lib" "${OUT_DIR}/autoconfig/" "${OUT_DIR}/downloads/" "${OUT_DIR}/system/" "${OUT_DIR}/screenshots/" "${OUT_DIR}/assets/" "${OUT_DIR}/overlays/" "${OUT_DIR}/saves/" "${OUT_DIR}/roms/" "${OUT_DIR}/remap/" "${OUT_DIR}/database/" "${OUT_DIR}/thumbnails/" "${OUT_DIR}/playlists"
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
    zip -rq "${OUT_DIR}/retroarch-rpi3.zip" "${OUT_DIR}"
}


# The main sequence of steps now go here ...
prerequisites
#build_retroarch
##build_libretro_all
build_libretro_select
install_libretro
extras_libretro
sync
exit 0

