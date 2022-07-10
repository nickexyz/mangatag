#!/usr/bin/env bash

######################################################################
# Config folder path, were to store the database.
######################################################################
config_path="/config"

script_path="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
if [ ! -f "$config_path"/mangatag.conf ] ; then
  cp "$script_path"/mangatag.conf.example "$config_path"/mangatag.conf.example
  echo "First run, an example config has been created."
  exit 0
fi
source "$config_path"/mangatag.conf

dbpath="$config_path/data.db"

if ! sqlite3 --version &> /dev/null ;
then
  echo "You need sqlite installed to use this script."
  exit 1
fi

if [[ "$1" == "interactive" ]]; then
  interactive="1"
elif [[ "$1" == "replace" ]]; then
  replace="1"
elif [[ "$1" == "auto" ]]; then
  auto="1"
elif [[ "$1" == "delete" ]]; then
  delete="1"
  delete_manga="$2"
else
  interactive=""
  replace=""
  delete=""
  auto=""
fi

check_lock() {
  if [ -f "$config_path"/mangatag.lock ];
  then
    echo "mangatag.sh is already running, exiting..."
    exit 0
  fi

  trap "rm -f $config_path/mangatag.lock ; exit" INT TERM EXIT
  touch "$config_path"/mangatag.lock
}

check_delete() {
  if [ "$delete" == "1" ]; then
    if [ -n "$delete_manga" ]; then
      for tbl in "${library[@]}"; do
        if [ -d "$tbl" ]; then
          if [ -d "$tbl/$delete_manga" ]; then
            echo "Deleting Cover.jpg and ComicInfo.xml for: $delete_manga"
            echo
            zero_chap=$( ls -1p "$tbl/$delete_manga" | grep -v / | grep " 0.cbz\| 00.cbz\|_00.cbz\|_0.cbz\|-0.cbz\|-00.cbz" | head -n 1 )
            check_chap_del() {
              if test "`find \"$tbl/$delete_manga/$this_chap\" -mmin +1`" ; then
                unzip -l "$tbl/$delete_manga/$this_chap" | grep -q "Cover.jpg"
                if [[ $? -eq 0 ]]; then
                  echo "Deleting Cover.jpg from: $tbl/$delete_manga/$this_chap"
                  zip -qd "$tbl/$delete_manga/$this_chap" Cover.jpg 2>/dev/null
                fi
                unzip -l "$tbl/$delete_manga/$this_chap" | grep -q "Cover.jpeg"
                if [[ $? -eq 0 ]]; then
                  echo "Deleting Cover.jpeg from: $tbl/$delete_manga/$this_chap"
                  zip -qd "$tbl/$delete_manga/$this_chap" Cover.jpeg 2>/dev/null
                fi
                unzip -l "$tbl/$delete_manga/$this_chap" | grep -q "Cover.png"
                if [[ $? -eq 0 ]]; then
                  echo "Deleting Cover.png from: $tbl/$delete_manga/$this_chap"
                  zip -qd "$tbl/$delete_manga/$this_chap" Cover.png 2>/dev/null
                fi
                echo
                unzip -l "$tbl/$delete_manga/$this_chap" | grep -q ComicInfo.xml
                if [[ $? -eq 0 ]]; then
                  echo "Deleting ComicInfo.xml from: $tbl/$delete_manga/$this_chap"
                  zip -qd "$tbl/$delete_manga/$this_chap" ComicInfo.xml 2>/dev/null
                fi
              fi
            }
            if [[ -f "$tbl/$delete_manga/$zero_chap" ]]; then
              this_chap="$zero_chap"
              check_chap_del
            fi
            first_chap=$( ls -1p "$tbl/$delete_manga" | grep -v / | grep " 1.cbz\| 01.cbz\|_01.cbz\|_1.cbz\|-1.cbz\|-01.cbz" | head -n 1 )
            if [[ -f "$tbl/$delete_manga/$first_chap" ]]; then
              this_chap="$first_chap"
              check_chap_del
            fi
            for cbz in "$tbl/$delete_manga"/*.cbz ; do
              if test "`find \"$cbz\" -mmin +5`" ; then
                unzip -l "$cbz" | grep -q ComicInfo.xml
                if [[ $? -eq 0 ]]; then
                  echo "Deleting ComicInfo.xml from: $cbz"
                  zip -qd "$cbz" ComicInfo.xml 2>/dev/null
                fi
              fi
            done
            sqlite3 "$dbpath" "DELETE FROM information WHERE folder_path = \"$tbl/$delete_manga\""
          fi
        fi
      done
      exit 0
    else
      echo "No manga folder name was provided"
      exit 0
    fi
  fi
}

runme() {
  sqlite3 "$dbpath" "CREATE TABLE IF NOT EXISTS information ( folder_path CHAR NOT NULL PRIMARY KEY, anilist_id INT, name_english CHAR, cover_image CHAR, desc CHAR, starting_year INT, starting_month INT, starting_day INT, name_romaji CHAR, genres CHAR, average_score CHAR, release_status CHAR, chapters INT, timestamp INT );"
  for tbl in "${library[@]}"; do
    if [ -d "$tbl" ]; then
      for di in "$tbl"/*/ ; do
        # Remove path and trailing slash
        dir=$( echo "$di" | sed "s|$tbl/||g" | sed 's:/*$::' )

        folder_path="$tbl/$dir"
        if [[ -d "$tbl/$dir" ]] && [ ! -f "$tbl/$dir/.ignore_metadata" ] ; then
          if [ "$replace" != "1" ]; then
            check_multiple_matches=$( sqlite3 "$dbpath" "SELECT anilist_id FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null | wc -l )
            # If we get multiple ID:s, delete the records and start over.
            # Not the cleanest solution, but it works.
            if (( check_multiple_matches > 1 )); then
              manga_id=""
              echo "Multiple Anilist ID:s found for: $dir, deleting them all."
              sqlite3 "$dbpath" "DELETE FROM information WHERE folder_path = \"$folder_path\""
            else
              manga_id=$( sqlite3 "$dbpath" "SELECT anilist_id FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null | head -n 1 )
            fi
          fi
          timestamp_now=$( date +%Y%m%d )
          timestamp_sleep() {
            timestamp_now=$( date +%Y%m%d )
            sqlite3 "$dbpath" "UPDATE information SET timestamp = \"$timestamp_now\" WHERE folder_path=\"$folder_path\";"
            if [ -n "$sleep_number" ]; then
              sleep "$sleep_number"
            fi
          }
          search_interactive() {
            # Get Anilist data
            echo
            echo "Searching Anilist.co for:"
            echo "$folder_path"
            echo
            $script_path/get_anilist.py "$dbpath" "$dir" "$folder_path"
            status=$?
            if [[ $status -ne 0 ]]; then
              echo "No Anilist ID found for $dir"
              read -r -p "Do you want to provide the Anilist ID yourself? [y/N] " response
              if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                echo "Enter the Anilist ID: "
                read manga_id
                if ! $script_path/get_anilist_by_id.py "$dbpath" "$dir" "$folder_path" "$manga_id" ; then
                  echo "Could not find a match..."
                  manga_id=""
                else
                echo "Got it, thanks!"
                fi
              fi
            else
              echo "Got it, thanks!"
              manga_id=$( cat /tmp/mangatag_id.tmp )
            fi
          }
          search_auto() {
            # Get Anilist data
            echo "Searching Anilist (auto) for: $dir"
            if $script_path/get_anilist_auto.py "$dbpath" "$dir" "$folder_path" ; then
              manga_id=$( cat /tmp/mangatag_id.tmp )
            else
              manga_id=""
            fi
          }
          search_by_id() {
            # Get Anilist data
            echo "Searching Anilist (by ID) for: $dir"
            if ! $script_path/get_anilist_by_id.py "$dbpath" "$dir" "$folder_path" "$manga_id" ; then
              manga_id=""
            fi
          }
          if [[ -z "$manga_id"  &&  "$interactive" == "1" ]]; then
            search_interactive
            timestamp_sleep
          elif [[ -z "$manga_id"  &&  "$auto" == "1" ]] || [ "$replace" == "1" ]; then
            search_auto
            timestamp_sleep
          fi
          if [ -n "$manga_id" ]; then
            sql_timestamp=$( sqlite3 "$dbpath" "SELECT timestamp FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            if [ -z "$sql_timestamp" ]; then
              search_by_id
              timestamp_sleep
              replace_this="1"
            else
              if [ -n "$metadata_stale" ]; then
                check_stale=$( expr $timestamp_now - $sql_timestamp  )
                if (( check_stale > metadata_stale )); then
                  search_by_id
                  timestamp_sleep
                  replace_this="1"
                fi
              fi
            fi
            sql_cover_image=$( sqlite3 "$dbpath" "SELECT cover_image FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_name_english=$( sqlite3 "$dbpath" "SELECT name_english FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_genres=$( sqlite3 "$dbpath" "SELECT genres FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_genres_clean=$( echo $sql_genres | sed 's/\[//g' | sed 's/\]//g' | sed "s/\'//g" )
            sql_starting_year=$( sqlite3 "$dbpath" "SELECT starting_year FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_starting_month=$( sqlite3 "$dbpath" "SELECT starting_month FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_starting_day=$( sqlite3 "$dbpath" "SELECT starting_day FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_average_score=$( sqlite3 "$dbpath" "SELECT average_score FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_name_romaji=$( sqlite3 "$dbpath" "SELECT name_romaji FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_desc=$( sqlite3 "$dbpath" "SELECT desc FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_desc_clean=$( echo $sql_desc | sed -e 's/&[^;]*;//g' | sed -e 's/<[^>]*>//g' | sed 's/[^[:alnum:] \.\,-]\+//g' | tr '\n' ' ' | tr -s " " )
            sql_release_status=$( sqlite3 "$dbpath" "SELECT release_status FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )
            sql_chapters=$( sqlite3 "$dbpath" "SELECT chapters FROM information WHERE folder_path=\"$folder_path\";" 2>/dev/null )

            # If null, set 0.
            re='^[0-9]+$'
            if ! [[ $sql_starting_year =~ $re ]] ; then
              sql_starting_year="0"
            fi
            if ! [[ $sql_starting_month =~ $re ]] ; then
              sql_starting_month="0"
            fi
            if ! [[ $sql_starting_day =~ $re ]] ; then
              sql_starting_day="0"
            fi

            # Set other name if any is empty
            if [ -z "$sql_name_english" ]; then
              sql_name_english="$sql_name_romaji"
            fi
            if [ -z "$sql_name_romaji" ]; then
              sql_name_romaji="$sql_name_english"
            fi

            cp "$script_path"/ComicInfo.xml.template /tmp/ComicInfo.xml
            if echo "$sql_cover_image" | grep -q "jpg" ; then
              wget -q "$sql_cover_image" -O /tmp/Cover.jpg
            elif echo "$sql_cover_image" | grep -q "jpeg" ; then
              wget -q "$sql_cover_image" -O /tmp/Cover.jpeg
            elif echo "$sql_cover_image" | grep -q "png" ; then
              wget -q "$sql_cover_image" -O /tmp/Cover.png
            else
              sql_cover_image=""
            fi
            if [ -n "$sql_name_english" ]; then
              sed -i "s/_NAME_ENGLISH_/$sql_name_english/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_NAME_ENGLISH_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_genres_clean" ]; then
              sed -i "s/_GENRES_/$sql_genres_clean/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_GENRES_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_starting_year" ]; then
              sed -i "s/_STARTING_YEAR_/$sql_starting_year/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_STARTING_YEAR_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_starting_month" ]; then
              sed -i "s/_STARTING_MONTH_/$sql_starting_month/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_STARTING_MONTH_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_starting_day" ]; then
              sed -i "s/_STARTING_DAY_/$sql_starting_day/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_STARTING_DAY_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_average_score" ]; then
              sed -i "s/_AVERAGE_SCORE_/$sql_average_score/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_AVERAGE_SCORE_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_name_romaji" ]; then
              sed -i "s/_NAME_ROMAJI_/$sql_name_romaji/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_NAME_ROMAJI_/-/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$sql_desc" ]; then
              sed -i "s|_DESC_|$sql_desc_clean|g" /tmp/ComicInfo.xml
            else
              sed -i "s/_DESC_/-/g" /tmp/ComicInfo.xml
            fi
            if [ "$sql_release_status" == "FINISHED" ]; then
              if [ -n "$sql_chapters" ]; then
                sed -i "s/_COUNT_/$sql_chapters/g" /tmp/ComicInfo.xml
              else
                sed -i "s/_COUNT_/-1/g" /tmp/ComicInfo.xml
              fi
            else
              sed -i "s/_COUNT_/-1/g" /tmp/ComicInfo.xml
            fi
            if [ -n "$manga_id" ]; then
              sed -i "s/_ANILIST_ID_/$manga_id/g" /tmp/ComicInfo.xml
            else
              sed -i "s/_ANILIST_ID_/-/g" /tmp/ComicInfo.xml
            fi
            # cat /tmp/ComicInfo.xml
            if [ -n "$sql_cover_image" ]; then
              check_chap() {
                if test "`find \"$tbl/$dir/$this_chap\" -mmin +5`" ; then
                  unzip -l "$tbl/$dir/$this_chap" | grep -q ComicInfo.xml
                  if [[ $? -ne 0 ]]; then
                    zip -qd "$tbl/$dir/$this_chap" ComicInfo.xml >/dev/null 2>&1
                    zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/ComicInfo.xml
                  fi
                  unzip -l "$tbl/$dir/$this_chap" | grep -q "Cover."
                  if [[ $? -ne 0 ]]; then
                    if [ -f "/tmp/Cover.jpg" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.jpg
                    elif [ -f "/tmp/Cover.jpeg" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.jpeg
                    elif [ -f "/tmp/Cover.png" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.png
                    fi
                  fi
                  if [ "$replace" == "1" ] || [ "$replace_this" == "1" ]; then
                    unzip -l "$tbl/$dir/$this_chap" | grep -q "Cover.jpg"
                    if [[ $? -eq 0 ]]; then
                      zip -qd "$tbl/$dir/$this_chap" Cover.jpg 2>/dev/null
                    fi
                    unzip -l "$tbl/$dir/$this_chap" | grep -q "Cover.jpeg"
                    if [[ $? -eq 0 ]]; then
                      zip -qd "$tbl/$dir/$this_chap" Cover.jpeg 2>/dev/null
                    fi
                    unzip -l "$tbl/$dir/$this_chap" | grep -q "Cover.png"
                    if [[ $? -eq 0 ]]; then
                      zip -qd "$tbl/$dir/$this_chap" Cover.png 2>/dev/null
                    fi
                    if [ -f "/tmp/Cover.jpg" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.jpg
                    elif [ -f "/tmp/Cover.jpeg" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.jpeg
                    elif [ -f "/tmp/Cover.png" ] ; then
                      zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/Cover.png
                    fi
                    unzip -l "$tbl/$dir/$this_chap" | grep -q ComicInfo.xml
                    # cat /tmp/ComicInfo.xml
                    zip -qd "$tbl/$dir/$this_chap" ComicInfo.xml >/dev/null 2>&1
                    zip -0 -qurj "$tbl/$dir/$this_chap" /tmp/ComicInfo.xml
                  fi
                fi
              }
              zero_chap=$( ls -1p "$folder_path" | grep -v / | grep " 0.cbz\| 00.cbz\|_00.cbz\|_0.cbz\|-0.cbz\|-00.cbz" | head -n 1 )
              if [[ -f "$tbl/$dir/$zero_chap" ]]; then
                this_chap="$zero_chap"
                check_chap
              fi
              first_chap=$( ls -1p "$folder_path" | grep -v / | grep " 1.cbz\| 01.cbz\|_01.cbz\|_1.cbz\|-1.cbz\|-01.cbz" | head -n 1 )
              if [[ -f "$tbl/$dir/$first_chap" ]]; then
                this_chap="$first_chap"
                check_chap
              fi
            fi
            for cbz in "$folder_path"/*.cbz ; do
              if test "`find \"$cbz\" -mmin +5`" ; then
                unzip -l "$cbz" | grep -q ComicInfo.xml
                if [[ $? -ne 0 ]]; then
                  zip -0 -qurj "$cbz" /tmp/ComicInfo.xml
                fi
                if [ "$replace" == "1" ] || [ "$replace_this" == "1" ]; then
                  zip -qd "$cbz" ComicInfo.xml 2>/dev/null
                  zip -0 -qurj "$cbz" /tmp/ComicInfo.xml
                fi
              fi
            done
            sql_cover_image=""
            sql_name_english=""
            sql_genres=""
            sql_genres_clean=""
            sql_starting_year=""
            sql_starting_month=""
            sql_starting_day=""
            sql_average_score=""
            sql_name_romaji=""
            sql_desc=""
            sql_desc_clean=""
            timestamp_now=""
            sql_timestamp=""
            check_multiple_matches=""
            replace_this=""
            rm -f /tmp/ComicInfo.xml
            rm -f /tmp/Cover.jpg 2>/dev/null
            rm -f /tmp/Cover.jpeg 2>/dev/null
            rm -f /tmp/Cover.png 2>/dev/null
            rm -f /tmp/mangatag_id.tmp
          else
            echo "Could not find an Anilist ID"
          fi
        else
          echo "$Folder $tbl/$dir does not exist, or .ignore_metadata file is present."
        fi
      done
    else
      echo "Folder $tbl does not exist"
    fi
  done
}

cleanup() {
  for tbl in "${library[@]}"; do
    if [ -d "$tbl" ]; then
      find "$tbl" -mindepth 1 -maxdepth 1 -type d >> /tmp/mangatag_allnames.tmp
    fi
  done
  oIFS=$IFS
  IFS=$'\n'
  for name in $(sqlite3 "$dbpath" "SELECT folder_path FROM information"); do
    if ! grep -q "$name" /tmp/mangatag_allnames.tmp; then
      echo "Deleting $name from db since it doesn't exist on disk."
      sqlite3 "$dbpath" "DELETE FROM information WHERE folder_path = \"$name\""
    fi
  done
  rm -f /tmp/mangatag_allnames.tmp
  IFS=$oIFS
}


sqlite3 "$dbpath" "VACUUM;"

check_lock
time_now=$( date )
echo "Start: $time_now"
check_delete
runme
cleanup
time_now=$( date )
echo "Finished: $time_now"

rm -f "$config_path"/mangatag.lock

exit 0

