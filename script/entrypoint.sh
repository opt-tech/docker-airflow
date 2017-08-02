#!/usr/bin/env bash

echo ==================================================
echo =                  ENTRYPOINT
echo ==================================================
echo

AIRFLOW_HOME="/usr/local/airflow"
TRY_LOOP="10"

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

# Run webserver or else
if [ "$1" = "webserver" ]; then
    echo "Initialize database..."
    airflow initdb

    INIT_CMD="/init_meta_db.py"
    if [ -e /instance/admin_user.json ]; then
        INIT_CMD="$INIT_CMD --admin /instance/admin_user.json"
    fi
    if [ -e /instance/connections.json ]; then
        INIT_CMD="$INIT_CMD --connections /instance/connections.json"
    fi
    if [ -e /instance/variables.json ]; then
        INIT_CMD="$INIT_CMD --variables /instance/variables.json"
    fi
    
    python $INIT_CMD

    exec airflow webserver
else
    sleep 10
    exec airflow "$@"
fi
