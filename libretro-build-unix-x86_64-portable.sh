#/bin/bash
#
# This script is used in order to build libretro-super
# retro in a portable Unix way.
#
# Requirements:
# sudo apt-get install linux-libc-dev mesa-common-dev libgl1-mesa-dev libxml2-dev libudev-dev libz-dev libpng-dev libavformat-dev libvulkan-dev libclang-dev
#

set -e -x

CURR_DIR=$(realpath ${0%/*})
LIBRETRO_REPO="https://github.com/libretro/libretro-super"
LIBRETRO_PATH="${CURR_DIR}/$(basename ${LIBRETRO_REPO})"
OUT_DIR="${CURR_DIR}/retroarch"

export LIBRETRO_DEVELOPER=0
export DEBUG=0
export CFLAGS="-O3 -fomit-frame-pointer -fpie -pie -flto=auto -mno-fsgsbase"
export CFLAGS="${CFLAGS} -march=x86-64-v2 -mtune=generic"
export CXXFLAGS="${CFLAGS}"
export ASFLAGS="${CFLAGS}"
export LDFLAGS="${LDFLAGS} -Wl,-O3 -Wl,--hash-style=gnu -Wl,--as-needed -Wl,--gc-sections"
export LDFLAGS="${LDFLAGS} -Wl,-z,defs -Wl,-z,now -Wl,-z,relro -Wl,-fuse-ld=gold -Wl,-flto"

export CC="gcc"
export CXX="g++"
export AS="as"
export AR="gcc-ar"
export LINK="ld.gold"
export STRIP="strip"


function gitclean()
{
    git gc --prune=now --aggressive
    git repack && git clean -dfx
    git reset --hard
}

function prerequisites()
{
    # Make sure we have libretro super and get inside, fetch if first time
    cd ${CURR_DIR}
    git clone "${LIBRETRO_REPO}" || true

    # Update the packages
    ( cd ${LIBRETRO_PATH} && gitclean && git pull )
    ( cd ${LIBRETRO_PATH}/retroarch && gitclean && git pull )

    # Pull dependencies
    ( cd "${LIBRETRO_PATH}" && ./libretro-fetch.sh )

    # Prepare build path
    rm -rf $(realpath "${OUT_DIR}") && mkdir -p $(realpath "${OUT_DIR}")

    # Temporary build path
    mkdir -p "${OUT_DIR}/tmp"
}

function build_retroarch()
{
    # Build retroarch
    ( cd "${LIBRETRO_PATH}/retroarch" && 
      make -j clean
      #./configure --help ; exit -1
      ./configure --enable-sse --enable-opengl --enable-vulkan --disable-xvideo --disable-cg --disable-v4l2 --disable-al --disable-jack --disable-rsound --disable-oss --disable-coreaudio --disable-roar --disable-ffmpeg --disable-videoprocessor --disable-sdl2 --disable-sdl --disable-kms --disable-cheevos --disable-imageviewer --disable-parport --disable-langextra --disable-update_assets --disable-screenshots --disable-accessibility --disable-builtinflac --enable-builtinzlib || exit -127
      time make -f Makefile -j || exit -99
      make DESTDIR="${OUT_DIR}/tmp" install )
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

    for elem in "${cores[@]}"
      do
        ( cd "${LIBRETRO_PATH}/libretro-${elem}"
          # Update and reset the core git repo
          gitclean && git pull
          # Back on libretro super instructions which also copies the *.so
          # https://buildbot.libretro.com/docs/compilation/ubuntu/
          cd "${LIBRETRO_PATH}" && ./libretro-build.sh ${elem} ) || continue
      done
}

function build_libretro_all()
{
    "${LIBRETRO_PATH}/libretro-build.sh"
}

function install_libretro()
{
    "${LIBRETRO_PATH}/libretro-install.sh" "${OUT_DIR}"

    # Organize our files in a portable structure
    mkdir -p "${OUT_DIR}/bin" \
             "${OUT_DIR}/cores-info" \
             "${OUT_DIR}/cores" \
             "${OUT_DIR}/shaders" \
             "${OUT_DIR}/lib" \
             "${OUT_DIR}/autoconfig/" \
             "${OUT_DIR}/downloads/" \
             "${OUT_DIR}/system/" \
             "${OUT_DIR}/screenshots/" \
             "${OUT_DIR}/assets/" \
             "${OUT_DIR}/overlays/" \
             "${OUT_DIR}/remaps/" \
             "${OUT_DIR}/database/" \
             "${OUT_DIR}/playlists"
    cp -avf "${OUT_DIR}/tmp/usr/local/bin/." "${OUT_DIR}/bin"
    cp -avf "${OUT_DIR}/../release-scripts/." "${OUT_DIR}/bin"
    cp -avf "${OUT_DIR}/tmp/etc/." "${OUT_DIR}/config"
    cp -avf "${OUT_DIR}/tmp/usr/local/share/retroarch/assets/." "${OUT_DIR}/assets"
    mv -vff "${OUT_DIR}/config/retroarch.cfg" "${OUT_DIR}/config/retroarch.cfg.bak"
    find "${OUT_DIR}" -name "*.info" -exec mv -vf \{\} "${OUT_DIR}/cores-info/" 2> /dev/null \;
    find "${OUT_DIR}" -name "*.so" -exec mv -vf \{\} "${OUT_DIR}/cores/" 2> /dev/null \;

    # Moving prebuilts
    cp -avf "${LIBRETRO_PATH}/retroarch/media/shaders_cg" "${OUT_DIR}/shaders"
    cp -avf "${LIBRETRO_PATH}/retroarch/media/autoconfig" "${OUT_DIR}/autoconfig/joypad"
    cp -avf "${LIBRETRO_PATH}/retroarch/media/libretrodb/." "${OUT_DIR}/database"

    # Cleanup left-overs and any .git files for distribution
    rm -rf "${OUT_DIR}/tmp"
    ( find "${OUT_DIR}" -type d -name ".git" \
      && find "${OUT_DIR}" -name ".gitignore" \
      && find "${OUT_DIR}" -name ".gitmodules" ) | xargs rm -rf
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
#prerequisites
build_retroarch
##build_libretro_all
build_libretro_select
install_libretro
extras_libretro
sync
exit 0

