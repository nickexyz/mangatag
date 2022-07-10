FROM docker.io/library/alpine:3.16.0

RUN \
  echo "**** install packages ****" && \
  apk add -U --update --no-cache --virtual=build-dependencies \
    gcc \
    build-base \
    python3-dev && \
  apk add -U --upgrade --no-cache \
    findutils \
    bash \
    sqlite \
    zip \
    jq \
    python3 \
    py3-numpy \
    py3-pip && \

  echo "**** Install AnilistPython ****" && \
  python3 -m pip install --upgrade pip && \
  pip3 install -U --no-cache-dir \
    wheel && \
  pip3 install -U --no-cache-dir \
    AnilistPython==0.1.3 && \

  pip3 cache purge && \

# Cleanup
  echo "**** cleanup ****" && \
  rm -rf \
    /tmp/* \
    /var/tmp/* \
    /root/.cache \
    $HOME/.cache && \
  ln -s \
    /usr/bin/python3 \
    /usr/bin/python && \
  apk del --purge \
    build-dependencies

ENV PATH="/app:${PATH}"

COPY ./mangatag.sh /app/mangatag.sh
COPY ./mangatag.conf.example /app/mangatag.conf.example
COPY ./get_anilist.py /app/get_anilist.py
COPY ./get_anilist_by_id.py /app/get_anilist_by_id.py
COPY ./get_anilist_auto.py /app/get_anilist_auto.py
COPY ./ComicInfo.xml.template /app/ComicInfo.xml.template

VOLUME /config

ENTRYPOINT ["/app/mangatag.sh"]
