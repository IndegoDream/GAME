#!/bin/bash
# Elite Online: start the server.   ./run_server.sh            (accounts via Supabase, see README.md)
#                                   ELITE_DEV=1 ./run_server.sh  (any name logs in -- testing only)
cd "$(dirname "$0")"
exec python3 elite_server.py
