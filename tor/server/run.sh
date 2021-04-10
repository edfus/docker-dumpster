#!/bin/ash

if test -f "/run/secrets/${SECRET}"; then
  serve -c ./config -p $(cat /run/secrets/${SECRET}) --no-prompt --set-e
else
  echo "/run/secrets/${SECRET} DOES NOT exist."
  echo $(ls /run/secrets)
fi
