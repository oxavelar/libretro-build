#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import time
import subprocess

path = os.path.dirname(__file__)

retro_dir = os.path.abspath(os.path.join(path, '..'))
retro_bin = os.path.join(retro_dir, 'bin/retroarch')
retro_cfg = os.path.join(retro_dir, 'config/retroarch.cfg')
retro_ref = os.path.join(retro_dir, 'bin/retroarch-update-playlists.py')


def retroarch_update():
    """ Will populate the retroarch playlists dynamically """
    retro_cmd = 'python ' + retro_ref
    subprocess.call([retro_cmd], shell=True)


def retroarch_launch():
    """ Executes our own breed of retroarch portable """
    retro_cmd = retro_bin + ' --config ' + retro_cfg
    os.environ['LD_LIBRARY_PATH'] = os.path.join(retro_dir, 'lib')
    subprocess.call([retro_cmd], shell=True)


def systemd_service_ready():
    """ Used to detect if we have already launched as systemd """
    query_cmd = 'systemctl | grep -q "%s"' % __file__
    if (os.system(query_cmd) == 0):
        return True
    else:
        return False


def systemd_service_spawn():
    """ Allows us to suspend Kodi by spawning as a systemd unit """
    try:
        import kodi
        systemd_cmd = 'systemd-run --scope --nice=-5 ' + os.path.abspath(__file__)
        os.system(systemd_cmd)
    except ImportError:
        exit(-17)


def retroarch_main():
    """ Steps that pauses the media center and executes retroarch """

    media_pause = lambda: os.system('systemd stop  kodi')
    media_start = lambda: os.system('systemd start kodi')

    try:
        retroarch_update()
        media_pause()
        retroarch_launch()
    except KeyboardInterrupt:
        pass
    finally:
        pass
        media_start()
        exit(0)


if __name__ == '__main__':
    """ When we detect LibreELEC this will start in a special way """
    if not systemd_service_ready() and 'LibreELEC' in os.uname():
        systemd_service_spawn()
    else:
        print('Executing normally')
        retroarch_main()

