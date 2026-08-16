#!/usr/bin/env bash

set -u

ACME_TAG=3.1.4
ACME_COMMIT=3661fd86b6304115e42f43910e6dd452ab9866d6

email_address=${1:-}
certificate_home=${2:-}
force_option=${3:-}

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: the ACME installer must be run as root." >&2
    exit 1
fi
if [ -z "${email_address}" ] || [ -z "${certificate_home}" ]; then
    echo "Usage: lnmp-install-acme EMAIL CERTIFICATE_HOME [FORCE_OPTION]" >&2
    exit 1
fi
if ! printf '%s' "${email_address}" | grep -Eq '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'; then
    echo "Error: invalid ACME account email address." >&2
    exit 1
fi
case "${force_option}" in
    ''|-f) ;;
    *)
        echo "Error: unsupported acme.sh installer option." >&2
        exit 1
        ;;
esac
case "${certificate_home}" in
    /usr/local/nginx/conf/ssl) ;;
    *)
        echo "Error: unsupported certificate directory." >&2
        exit 1
        ;;
esac

acme_temp=$(mktemp -d /tmp/lnmp-acme.XXXXXX)
trap 'rm -rf -- "${acme_temp}"' EXIT HUP INT TERM
git clone --quiet --depth 1 --branch "${ACME_TAG}" https://github.com/acmesh-official/acme.sh.git "${acme_temp}/acme.sh" || exit 1
actual_commit=$(git -C "${acme_temp}/acme.sh" rev-parse HEAD)
if [ "${actual_commit}" != "${ACME_COMMIT}" ]; then
    echo "Error: acme.sh source verification failed." >&2
    exit 1
fi

cd "${acme_temp}/acme.sh" || exit 1
install -d -m 0700 "${certificate_home}" /usr/local/acme.sh/certs
if [ -n "${force_option}" ]; then
    ./acme.sh --install "${force_option}" --log --home /usr/local/acme.sh --certhome /usr/local/acme.sh/certs -m "${email_address}"
else
    ./acme.sh --install --log --home /usr/local/acme.sh --certhome /usr/local/acme.sh/certs -m "${email_address}"
fi
