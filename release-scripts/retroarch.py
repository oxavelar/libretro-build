#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import subprocess

path = os.path.dirname(__file__)

retro_dir = os.path.abspath(os.path.join(path, '..'))
retro_bin = os.path.join(retro_dir, 'bin/retroarch')
retro_cfg = os.path.join(retro_dir, 'config/retroarch.cfg')
retro_ref = os.path.join(retro_dir, 'bin/retroarch-update-playlists.py')

os.environ['LD_LIBRARY_PATH'] = os.path.join(retro_dir, 'lib')

retro_cmd = retro_bin + ' --config ' + retro_cfg
retro_ref = 'python ' + retro_ref
media_stop = 'systemctl stop kodi'
media_start = 'systemctl start kodi'

try:
    subprocess.call([retro_ref], shell=True)
    os.system(media_stop)
    subprocess.call([retro_cmd], shell=True)
except KeyboardInterrupt:
    pass
finally:
    os.system(media_start)

