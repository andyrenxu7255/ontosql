#!/bin/bash
set -e

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"

MIN_PASSWORD_LENGTH=8
if [ "${#POSTGRES_PASSWORD}" -lt "$MIN_PASSWORD_LENGTH" ]; then
    echo "ERROR: POSTGRES_PASSWORD must be at least $MIN_PASSWORD_LENGTH characters long" >&2
    exit 1
fi

printf '"postgres" "%s"\n' "$POSTGRES_PASSWORD" > /etc/pgbouncer/userlist.txt
chmod 600 /etc/pgbouncer/userlist.txt

unset POSTGRES_PASSWORD

exec pgbouncer /etc/pgbouncer/pgbouncer.ini
