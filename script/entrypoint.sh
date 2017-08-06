#!/usr/bin/env bash

echo ==================================================
echo =                  ENTRYPOINT                    =
echo ==================================================
echo

AIRFLOW__CORE__AIRFLOW_HOME="/usr/local/airflow"
TRY_LOOP="10"

: ${REDIS_HOST:="redis"}
: ${REDIS_PORT:="6379"}

: ${POSTGRES_HOST:="postgres"}
: ${POSTGRES_PORT:="5432"}
: ${POSTGRES_USER:="airflow"}


echo ">>> Setting up core fernet key..."
if [ -z "$AIRFLOW__CORE__FERNET_KEY" ]; then
    if ! [ -e /instance/fernet.key ]; then
        >&2 echo "Unsecured installation, exit."
        exit 1
    fi

    echo "Use fernet.key file."
    AIRFLOW__CORE__FERNET_KEY=$(cat /instance/fernet.key)
else
    echo "Use fernet key from env."
fi

echo ">>> Setting up webserver secret key..."
if [ -z "$AIRFLOW__WEBSERVER__SECRET_KEY" ]; then
    if ! [ -e /instance/fernet.key ]; then
        >&2 echo "Unsecured installation, exit."
        exit 1
    fi

    echo "Use fernet.key file."
    AIRFLOW__WEBSERVER__SECRET_KEY=$(cat /instance/fernet.key)
else
    echo "Use secret key from env."
fi


# For information only, very dangerous if generating a new key whereas some stuff is already stored crypted.
#: ${AIRFLOW__CORE__FERNET_KEY:=$(python -c "from cryptography.fernet import Fernet; FERNET_KEY = Fernet.generate_key().decode(); print(FERNET_KEY)")}

if [ -e "/requirements.txt" ]; then
    echo "==========================="
    echo "Install python requirements"
    echo "==========================="
    pip install --user -r /requirements.txt
fi

# Wait for postgres server ready
if [ "$1" = "webserver" ] || [ "$1" = "worker" ] || [ "$1" = "scheduler" ] ; then
  i=0
  while ! nc -z $POSTGRES_HOST $POSTGRES_PORT >/dev/null 2>&1 < /dev/null; do
    i=$((i+1))
    if [ "$1" = "webserver" ]; then
      echo "$(date) - waiting for ${POSTGRES_HOST}:${POSTGRES_PORT}... $i/$TRY_LOOP"
      if [ $i -ge $TRY_LOOP ]; then
        echo "$(date) - ${POSTGRES_HOST}:${POSTGRES_PORT} still not reachable, giving up"
        exit 1
      fi
    fi
    sleep 10
  done
fi

# Wait for redis server ready
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

echo "==========================="
echo "Start program              "
echo "==========================="
if [ "$1" = "webserver" ]; then
    echo ">>> Initialize database"
    airflow initdb

    echo ">>> Configure metadata"
    python /init_meta_db.py --admin /instance/admin_user.json --connections /instance/connections.json --variables /instance/variables.json

    echo ">>> Run webserver"
    exec airflow webserver
else
    echo ">>> Run $1"
    exec airflow "$@"
fi
