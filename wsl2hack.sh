#!/bin/bash
# your WSL2 username
UNAME="cisien"

UUID=$(id -u "${UNAME}")
UGID=$(id -g "${UNAME}")
UHOME=$(getent passwd "${UNAME}" | cut -d: -f6)
USHELL=$(getent passwd "${UNAME}" | cut -d: -f7)

if [[ -p /dev/stdin || "${BASH_ARGC}" > 0 && "${BASH_ARGV[1]}" != "-c" ]]; then
    USHELL=/bin/bash
fi

if [[ "${PWD}" = "/root" ]]; then
    cd "${UHOME}"
fi

# get pid of systemd
SYSTEMD_PID=$(pgrep -xo systemd)

# if we're already in the systemd environment
if [[ "${SYSTEMD_PID}" -eq "1" ]]; then
    exec "${USHELL}" "$@"
fi

if [[ -z ${SYSTEMD_PID} ]]; then
    # start systemd
    /usr/bin/daemonize -l "${HOME}/.systemd.lock" /usr/bin/unshare -fp --mount-proc /lib/systemd/systemd --system-unit=basic.target

    # wait for systemd to start
    retries=50
    while [[ -z ${SYSTEMD_PID} && $retries -ge 0 ]]; do
        (( retries-- ))
            sleep .1
            SYSTEMD_PID=$(pgrep -xo systemd)
    done

    if [[ $retries -lt 0 ]]; then
        >&2 echo "Systemd timed out; aborting."
        exit 1
    fi
fi

# export WSL variables
export WINPATH="$(echo "$PATH"|grep -o ':/mnt/c.*$'|sed 's!^:!!')"
RUNOPTS=""
RUNOPTS="$RUNOPTS -l"
RUNOPTS="$RUNOPTS -w WINPATH"
RUNOPTS="$RUNOPTS -w WSL_INTEROP"
RUNOPTS="$RUNOPTS -w WSL_DISTRO_NAME"
RUNOPTS="$RUNOPTS -w VSCODE_WSL_EXT_LOCATION"
RUNOPTS="$RUNOPTS -w HOSTTYPE"
RUNOPTS="$RUNOPTS -w LANG"
RUNOPTS="$RUNOPTS -w NAME"
RUNOPTS="$RUNOPTS -w WSLENV"
RUNOPTS="$RUNOPTS -w DISPLAY"

echo "${@}"
# enter systemd namespace
exec /usr/bin/nsenter -t "${SYSTEMD_PID}" -m -p --wd="${PWD}" /sbin/runuser $RUNOPTS -s "${USHELL}" "${UNAME}" -- "${@}"
