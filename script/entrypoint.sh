#!/usr/bin/env bash

echo ==================================================
echo =                  ENTRYPOINT
echo ==================================================
echo

AIRFLOW_HOME="/usr/local/airflow"
TRY_LOOP="10"

: ${REDIS_HOST:="redis"}
: ${REDIS_PORT:="6379"}

: ${POSTGRES_HOST:="postgres"}
: ${POSTGRES_PORT:="5432"}
: ${POSTGRES_USER:="airflow"}

if [ -z "$AIRFLOW__CORE__FERNET_KEY" ]; then
    if ! [ -e /instance/fernet.key ]; then
        echo "Unsecured installation, exit."
        exit 1
    fi

    echo "Use fernet.key file."
    AIRFLOW__CORE__FERNET_KEY=$(cat /instance/fernet.key)
else
    echo "Use fernet key from env."
fi

# For information only, very dangerous if generating a new key whereas some stuff is already stored crypted.
#: ${AIRFLOW__CORE__FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}


# Install custome python package if requirements.txt is present
if [ -e "/requirements.txt" ]; then
    pip install --user -r /requirements.txt
fi

# Wait for Postresql
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
    until psql -h "$POSTGRES_HOST:$POSTGRES_PORT" -U "$POSTGRES_USER" -c '\l'; do
      >&2 echo "Postgres is unavailable - sleeping"
      sleep 5
    done
fi

# Wait for Redis
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] || [ "$1" = "flower" ] ; then
    j=0
    while ! nc -z $REDIS_HOST $REDIS_PORT >/dev/null 2>&1 < /dev/null; do
        j=$((j+1))
        if [ $j -ge $TRY_LOOP ]; then
            echo "$(date) - $REDIS_HOST still not reachable, giving up"
            exit 1
        fi
        echo "$(date) - waiting for Redis... $j/$TRY_LOOP"
        sleep 5
    done
fi

# Run webserver or else
if [ "$1" = "webserver" ]; then
    echo "Initialize database..."
    airflow initdb

    python /init_meta_db.py --admin /instance/admin_user.json --connections /instance/connections.json --variables /instance/variables.json

    exec airflow webserver
else
    sleep 10
    exec airflow "$@"
fi
