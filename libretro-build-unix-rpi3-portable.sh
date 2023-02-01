#/bin/bash
#
# This script is used in order to build libretro-super
# retro in a portable Unix way.
#
# Requirements:
# sudo apt-get install crossbuild-essential-armhf linux-libc-dev:armhf libz-dev:armhf libpng-dev:armhf libavformat-dev:armhf

set -e -x

CURR_DIR=$(realpath ${0%/*})
LIBRETRO_REPO="https://github.com/libretro/libretro-super"
LIBRETRO_PATH="${CURR_DIR}/$(basename ${LIBRETRO_REPO})"
DISTDIR="${CURR_DIR}/retroarch"

export LIBRETRO_DEVELOPER=0
export DEBUG=0
export CFLAGS="-O3"
export CFLAGS="${CFLAGS} -march=armv8-a+crc -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard -mvectorize-with-neon-quad"
export CXXFLAGS="${CFLAGS}"
export ASFLAGS="${CFLAGS}"
export LDFLAGS="${LDFLAGS} -Wl,-O3 -Wl,--hash-style=gnu -Wl,--as-needed -Wl,--gc-sections"
export LDFLAGS="${LDFLAGS} -Wl,-z,defs -Wl,-z,now -Wl,-z,relro -Wl,-fuse-ld=gold -Wl,-flto"

export CROSS_COMPILE="/usr/bin/arm-linux-gnueabihf-"
export CC="${CROSS_COMPILE}gcc -L${CURR_DIR}/rpi-firmware/hardfp/opt/vc/lib/ -I${CURR_DIR}/rpi-firmware/hardfp/opt/vc/include/ -I/usr/include/arm-linux-gnueabihf/"
export CXX="${CROSS_COMPILE}g++ -L${CURR_DIR}/rpi-firmware/hardfp/opt/vc/lib/ -I${CURR_DIR}/rpi-firmware/hardfp/opt/vc/include/ -I/usr/include/arm-linux-gnueabihf/"
export AS="${CROSS_COMPILE}as"
export AR="${CROSS_COMPILE}gcc-ar"
export LINK="${CROSS_COMPILE}ld"
export STRIP="${CROSS_COMPILE}strip"


function gitclean()
{
    git gc --prune=now --aggressive
    git repack && git clean -dfx
    git reset --hard
}

function prerequisites()
{
    # Raspberry firmware include files used for compiling
    cd ${CURR_DIR}
    # git clone -b master --single-branch "https://github.com/raspberrypi/firmware" "rpi-firmware" \
    #  || $(cd "rpi-firmware" && git gc --prune=now && git clean -dfx && git reset --hard && git pull)
    

    # Make sure we have libretro super and get inside, fetch if first time
    cd ${CURR_DIR}
    git clone "${LIBRETRO_REPO}" || true

    # Update the packages
    ( cd ${LIBRETRO_PATH} && gitclean && git pull )
    ( cd ${LIBRETRO_PATH}/retroarch && gitclean && git pull )

    # Pull dependencies
    ( cd "${LIBRETRO_PATH}" && ./libretro-fetch.sh )

    # Prepare build path
    rm -rf $(realpath "${DISTDIR}") && mkdir -p $(realpath "${DISTDIR}")

    # Temporary build path
    mkdir -p "${DISTDIR}/tmp"
}

function build_retroarch()
{
    # Build retroarch
    ( cd "${LIBRETRO_PATH}/retroarch" && 
      make -j clean
      #./configure --help ; exit -1
      ./configure --enable-neon --enable-opengles --disable-vulkan --disable-xvideo --disable-cg --disable-v4l2 --disable-al --disable-jack --disable-rsound --disable-oss --disable-coreaudio --disable-roar --disable-ffmpeg --disable-videoprocessor --disable-sdl2 --disable-sdl --disable-wayland --disable-kms --disable-cheevos --disable-imageviewer --disable-parport --disable-langextra --disable-update_assets --disable-miniupnpc || exit -127
      time make -f Makefile -j || exit -99
      make DESTDIR="${DISTDIR}/tmp" install )
}

function build_libretro_select()
{
    cores=(
            "snes9x"
            "mupen64plus_next"
            "dolphin"
            "mgba"
            "ppsspp"
            "nestopia"
            "beetle_psx"
            "mame"
    )

    ( cd "${LIBRETRO_PATH}" && echo -n "" > .cores-recipe
      # Select core recipes into a temporary recipe
      for core in "${cores[@]}"
        do
          sed -n "/^${core}\s/p" recipes/linux/cores-linux-armhf-generic >> .cores-recipe
        done

      # Build the list
      cp -af recipes/linux/cores-linux-armhf-generic.conf .cores-recipe.conf
      FORCE=YES EXIT_ON_ERROR=0 ./libretro-buildbot-recipe.sh .cores-recipe )
}

function install_libretro()
{
    "${LIBRETRO_PATH}/libretro-install.sh" "${DISTDIR}"

    # Organize our files in a portable structure
    mkdir -p "${DISTDIR}/bin" \
             "${DISTDIR}/cores-info" \
             "${DISTDIR}/cores" \
             "${DISTDIR}/shaders" \
             "${DISTDIR}/lib" \
             "${DISTDIR}/autoconfig/" \
             "${DISTDIR}/downloads/" \
             "${DISTDIR}/system/" \
             "${DISTDIR}/screenshots/" \
             "${DISTDIR}/assets/" \
             "${DISTDIR}/overlays/" \
             "${DISTDIR}/remaps/" \
             "${DISTDIR}/database/" \
             "${DISTDIR}/playlists"
    cp -avf "${DISTDIR}/tmp/usr/local/bin/." "${DISTDIR}/bin"
    cp -avf "${DISTDIR}/../release-scripts/." "${DISTDIR}/bin"
    cp -avf "${DISTDIR}/../release-package/." "${DISTDIR}/bin"
    cp -avf "${DISTDIR}/tmp/etc/." "${DISTDIR}/config"
    cp -avf "${DISTDIR}/tmp/usr/local/share/retroarch/assets/." "${DISTDIR}/assets"
    mv -uvf "${DISTDIR}/config/retroarch.cfg" "${DISTDIR}/config/retroarch.cfg.bak"
    find "${DISTDIR}/" -name "*.so" -exec mv -vf \{\} "${DISTDIR}/cores/" 2> /dev/null \;
    find "${DISTDIR}/" -name "*.info" -exec mv -vf \{\} "${DISTDIR}/cores-info/" 2> /dev/null \;

    # Moving prebuilts
    cp -avf "${LIBRETRO_PATH}/retroarch/media/shaders_cg" "${DISTDIR}/shaders"
    cp -avf "${LIBRETRO_PATH}/retroarch/media/autoconfig" "${DISTDIR}/autoconfig/joypad"
    cp -avf "${LIBRETRO_PATH}/retroarch/media/libretrodb/." "${DISTDIR}/database"

    # Cleanup left-overs and any .git files for distribution
    rm -rf "${DISTDIR}/tmp"
    ( find "${DISTDIR}" -type d -name ".git" \
      && find "${DISTDIR}" -name ".gitignore" \
      && find "${DISTDIR}" -name ".gitmodules" ) | xargs rm -rf
}

function extras_libretro()
{
    # Convert shaders
    "${LIBRETRO_PATH}/retroarch/tools/cg2glsl.py" "${DISTDIR}/shaders/shaders_cg" "${DISTDIR}/shaders/shaders_glsl"
    
    # Strip out debug symbols from the shared libraries and main binary
    ${STRIP} --strip-debug --strip-unneeded --remove-section=.comment --remove-section=.note ${DISTDIR}/cores/*.so
    ${STRIP} --strip-debug --strip-unneeded --remove-section=.comment --remove-section=.note ${DISTDIR}/bin/retroarch

    # ack for archival
    zip -rq "${DISTDIR}/retroarch-rpi3.zip" "${DISTDIR}"
}


# The main sequence of steps now go here ...
prerequisites
build_retroarch
build_libretro_select
install_libretro
extras_libretro
sync
exit 0

