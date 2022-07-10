
This is a tool that updates cbz files with ComicInfo.xml, and the first chapter will have a Cover.jpg added as well.
The information is taken from Anilist.
It is made to tag Manga for Kavita (https://github.com/Kareadita/Kavita)

Personally, I use this in combination with https://github.com/nickexyz/ntfy-shellscripts/blob/main/read_notify.sh for notifications when new chapters are imported.

Most metadata will be the same for all files within a series.
For example, release date will be the date of the first chapter.
I may fix those things in the future.

When the naming is made by Tachiyomi, it seems to work well, but no guarantees.


The file structure of the manga should be something like this:
"/path/mangalibrary1/manga name/chapter one.cbz"

If not running in docker, you will need to install AnilistPython (https://github.com/ReZeroE/AnilistPython)

Example:
<pre>
pip install AnilistPython==0.1.3
</pre>
Then you will need to change config_path in mangatag.sh.

If you choose to run in Docker, you usually put something like this in crontab:
Example: docker run --rm -it -v /path/to/configfolder:/config -v /path/to/library:/library mangatag

The first time you run the container, an example configfile will be created in /config/mangatag.conf.example (If you run with docker)
Rename it to mangatag.conf

When run without "interactive", the script will only use local metadata since choices need to be made when adding new series.
If you want to add medatada to new manga series, use "interactive"

Example:
<pre>
docker run --rm -it -v /path/to/configfolder:/config -v /path/to/library:/library mangatag interactive
</pre>


Auto does the same as interactive, but the first choice will be used which means it can be run unattended.

Example: 
<pre>
docker run --rm -it -v /path/to/configfolder:/config -v /path/to/library:/library mangatag auto
</pre>


If you want to replace all existing metadata, use "replace"
This do the same as auto, but every manga will be looked up at Anilist and metadata will be replaced.

Example: 
<pre>
docker run --rm -it -v /path/to/configfolder:/config -v /path/to/library:/library mangatag replace
</pre>

If you want to delete ComicInfo.xml and the cover from a series, use "delete"
The string after delete should be the folder name.

Example: 
<pre>
docker run --rm -it -v /path/to/configfolder:/config -v /path/to/library:/library mangatag delete "Call of the Night"
</pre>


If you want to exclude a manga from the scan, simply create a .ignore_metadata file in the series folder.

Example:
<pre>
/path/mangalibrary1/manga1/.ignore_metadata
</pre>

An image is available here: https://hub.docker.com/r/nickexyz/mangatag
