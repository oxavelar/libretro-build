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
DISTDIR="${CURR_DIR}/retroarch"

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
      ./configure --enable-sse --enable-opengl --enable-vulkan --disable-ffmpeg --disable-videoprocessor --disable-cheevos --disable-imageviewer --disable-parport --disable-langextra --disable-update_assets --disable-screenshots --disable-accessibility --disable-builtinflac --enable-builtinzlib || exit -127
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
          sed -n "/^${core}\s/p" recipes/linux/cores-linux-x64-generic >> .cores-recipe
        done

      # Build the list
      cp -af recipes/linux/cores-linux-x86-generic.conf .cores-recipe.conf
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
    mv -vff "${DISTDIR}/config/retroarch.cfg" "${DISTDIR}/config/retroarch.cfg.bak"
    find "${LIBRETRO_PATH}/dist" -name "*.info" -exec mv -vf \{\} "${DISTDIR}/cores-info/" 2> /dev/null \;
    find "${LIBRETRO_PATH}/dist" -name "*.so" -exec mv -vf \{\} "${DISTDIR}/cores/" 2> /dev/null \;

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

    # Pack for archival
    zip -rq "${DISTDIR}/retroarch-x86_64.zip" "${DISTDIR}"
}


# The main sequence of steps now go here ...
prerequisites
build_retroarch
build_libretro_select
install_libretro
extras_libretro
sync
exit 0

