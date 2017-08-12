#!/usr/bin/env python
# -*- coding: UTF-8 -*-

import os
import sys
import glob
import time
import zipfile
import difflib
import functools

roms_folder = '../roms/'
playlists_folder = '../playlists/'
thumbnail_folder = '../thumbnails/'


def detect_rom_from_file(file):
    """
    Figures out the zip file and understands the name
    and console to be used for the retroarch *.lpl's.
    """
    retrofile = get_file_name(file)
    console = get_console_name(file)
    gamename = get_game_name(file, console)
    
    return retrofile, gamename, console


def get_file_name(file):
    """
    Specific convention for the *.zip files for the *.lpl's.
    """
    rfile = os.path.relpath(file)
    
    # Workaround for Linux where absolute path is needed
    if sys.platform == 'linux2': rfile = os.path.abspath(file)
    
    # Figure out the retroarch's filename to use
    if file.endswith('.zip'):
        mainfile = zipfile.ZipFile(file).namelist()[0]
        return rfile + '#' + mainfile
    else:
        return rfile


def get_game_name(file, console=None, fuzz_ratio=0.67):
    """
    If there is a potential thumbnail that has very high fuzz ratio
    please return the updated name. Since retroarch uses specific
    names for the thumbnail data.
    """
    # Coarse approach at getting the name from filename
    gamename = os.path.splitext(os.path.basename(file))[0]
    
    # If there is a potential thumbnail matching the name use it
    thumb_folder = os.path.join(thumbnail_folder, console)
    thumb_folder = os.path.join(thumb_folder, 'Named_Snaps')
    
    # Extracts just the filename without extension for all of the thumbs
    thumbs = glob.glob(os.path.join(thumb_folder, '*.png'))
    thumbs = [os.path.splitext(os.path.basename(t))[0] for t in thumbs]
    
    # Obtains the fuzz ratio of them all and get the closest hit
    fuzz = lambda x, y: difflib.SequenceMatcher(None, y, x).quick_ratio()
    fuzzer = functools.partial(fuzz, gamename)
    ratios = map(fuzzer, thumbs)
    fuzzed = tuple(zip(thumbs, ratios))
    
    name, ratio = max(fuzzed, key=lambda p: p[1]) if len(fuzzed) else tuple(('', 0))
    
    # Update if we find that our match looks good with the thumbs name
    if ratio > fuzz_ratio:
        return name
    else:
        return gamename


def get_console_name(file):
    """
    Using a hashmap for converting my own console name
    to retroarch's way.
    """
    console =  os.path.basename(os.path.dirname(file))
    
    map = { \
            'gb'        : 'Nintendo - Game Boy',
            'gbc'       : 'Nintendo - Game Boy Color',
            '3ds'       : 'Nintendo - Nintendo 3DS',
            'gba'       : 'Nintendo - Game Boy Advance',
            'nes'       : 'Nintendo - Nintendo Entertainment System',
            'psx'       : 'Sony - PlayStation',
            'ps2'       : 'Sony - PlayStation 2',
            'ps3'       : 'Sony - PlayStation 3',
            'snes'      : 'Nintendo - Super Nintendo Entertainment System',
            'arcade'    : 'FB Alpha - Arcade Games',
            'n64'       : 'Nintendo - Nintendo 64',
            'psp'       : 'Sony - PlayStation Portable',
            'gamecube'  : 'Nintendo - GameCube',
            'wii'       : 'Nintendo - Wii',
    }
    try:
        name = map[console]
    except KeyError:
        name = ''

    return name


def lpl_entry_write(playlist, path, name):
    """
    The formatting of the *.lpl files of retroarch is similar to:
    
        (ROM Path)
        (ROM Name)
        DETECT
        DETECT
        0|crc
        
    Using this to write the specific entry and playlist.
    """
    playlist = os.path.join(playlists_folder, playlist)
    
    with open(playlist, 'a+') as f:
        f.write(path + '\n')
        f.write(name + '\n')
        f.write('DETECT' + '\n')
        f.write('DETECT' + '\n')
        f.write('0|crc' + '\n')
        f.write('\n')


def update_playlists():
    """
    Will traverse the ROM directory name and start
    populating *.lpl's regarding the games.
    """
    print('I: Generating dynamic retroarch *.lpl\'s ...')
    time_start = time.time()
    for dirpath, dnames, fnames in os.walk(roms_folder):
        for f in fnames:
            # Extract the full filename path
            filepath = os.path.join(dirpath, f)
            retro_file, game_name, console_name = detect_rom_from_file(filepath)
            # Using the filename without extension as human name
            lpl_filename = console_name + '.lpl'
            lpl_entry_write(lpl_filename, retro_file, game_name)
    time_spent = time.time() - time_start
    print('I: Updated the retroarch playlists in %0.3f seconds' % time_spent)


def purge_playlists():
    """
    Will cleanup any *.lpl file present, assuming that
    everything under ROM's will get refreshed later.
    """
    for lpl in glob.glob(os.path.join(playlists_folder, '*.lpl')):
        os.remove(lpl)


def main():
    # Change to our current directory
    os.chdir(os.path.dirname(os.path.realpath(__file__)))
    # Remove pre-existing playlists
    purge_playlists()
    # Start detecting the games and populating
    update_playlists()


if __name__ == '__main__':
    main()

