#!/usr/bin/env bash
set -euo pipefail
source /etc/duckdns.env
: "${DUCKDNS_DOMAIN:?}"
: "${DUCKDNS_TOKEN:?}"
result=$(curl --fail --silent --show-error --max-time 30 --get 'https://www.duckdns.org/update' --data-urlencode "domains=$DUCKDNS_DOMAIN" --data-urlencode "token=$DUCKDNS_TOKEN" --data-urlencode 'ip=')
[[ "$result" == OK ]]
