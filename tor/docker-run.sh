#!/bin/bash

# set -x
set -e # exits when errored

readonly TOR_PATH=./tor

mkdir -p ${TOR_PATH}/tmp
cat >${TOR_PATH}/tmp/torrc <<EOF
HiddenServiceDir /app
HiddenServiceVersion 3
HiddenServicePort 80 file_server:12345
Log notice stdout
EOF

read -e -p "Enter the location of onion keys: " VAR_LOCAL_VOL

echo -----
if [ -d "$VAR_LOCAL_VOL" ]; then
  cp -r $VAR_LOCAL_VOL/. ${TOR_PATH}/tmp
  echo "Hostname: $(cat ${TOR_PATH}/tmp/hostname)"
else
  mkdir -p tor
  echo "For onion hostname"
  echo 'Do docker exec $(docker ps | grep tor_tor | gawk -F " " "{ print $1 }") cat /app/hostname'
fi
echo -----
set +e
bash ./log-hostname.sh &
docker-compose up --build 

rm -r ${TOR_PATH}/tmp