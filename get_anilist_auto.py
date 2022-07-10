#!/usr/bin/env python

import sys, os, sqlite3, re
con = sqlite3.connect(sys.argv[1])

from AnilistPython import Anilist
anilist = Anilist()

# Get ID
tmpfilePath = '/tmp/mangatag_id.tmp';
if os.path.exists(tmpfilePath):
    os.remove(tmpfilePath)
manga_id = anilist.get_manga_id(sys.argv[2], manual_select=False)

file = open('/tmp/mangatag_id.tmp', 'w')
str_manga_id = repr(manga_id)
file.write(str_manga_id)
file.close()


# Get desc
manga_desc = anilist.get_manga_with_id(manga_id)

mangaMonth, mangaDay, mangaYear = manga_desc['starting_time'].split('/', 3)

# Strip extra chars for genres
locals().update(manga_desc)
str_genres = repr(genres)
def processString4(str_genres):
  str_genres, n = re.subn('[][]', '', str_genres)
  str_genres, n = re.subn('\'', '', str_genres)
processString4(str_genres)

con.execute("INSERT OR IGNORE INTO information(folder_path) VALUES (?)", (sys.argv[3],))
con.execute('UPDATE information SET anilist_id = ? , name_english = ? , cover_image = ? , desc = ? , starting_year = ? , starting_month = ? , starting_day = ? , name_romaji = ? , genres = ? , average_score = ? , release_status = ? , chapters = ? WHERE folder_path = ?', [str_manga_id, manga_desc['name_english'], manga_desc['cover_image'], manga_desc['desc'], mangaYear, mangaMonth, mangaDay, manga_desc['name_romaji'], str_genres, manga_desc['average_score'], manga_desc['release_status'], manga_desc['chapters'], sys.argv[3]])

con.commit()
con.close()
