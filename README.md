# wsl2-hacks - Updated for Ubuntu 20.04 / 20.10
---
## Systemd

With this setup your shells will be able to run `systemctl` commands, have auto-starting services, as well as be able to run [snaps](https://tutorials.ubuntu.com/tutorial/basic-snap-usage).

1. Install deps

    ```shell
    $ sudo apt update
    $ sudo apt install dbus policykit-1 daemonize
    ```

1. Create a fake-`bash`

    This fake shell will intercept calls to `wsl.exe bash ...` and forward them to a real bash running in the right environment for `systemd`. If this sounds like a hack-- well, it is. However, I've tested various workflows and use this daily. That being said, your mileage may vary.

    ```
    $ sudo touch /usr/local/bin/wsl2hack
    $ sudo chmod +x /usr/local/bin/wsl2hack
    $ sudo editor /usr/local/bin/wsl2hack
    ```
        
    Add the following, be sure to replace `<YOURUSER>` with your WSL2 Linux username

    ```sh
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
    ```

1. Set the fake-`bash` as our `root` user's shell

    We need `root` level permission to get `systemd` setup and enter the environment. The way I went about solving this is to
    have WSL2 default to the `root` user and when `wsl.exe` is executed the fake-`bash` will do the right thing.
    
    The next step in getting this working is to change the default shell for our `root` user.
    
    Edit the `/etc/passwd` file:
    
    `$ vipw` - edits `/etc/passwd`
    
    Find the line starting with `root:`, it should be the first line.
    Edit this line line:
    
    `root:x:0:0:root:/root:/usr/local/bin/wsl2hack`
    
    Save and close this file.
    
1. Restart WSL

    The next step is to shutdown WSL2.

    In a PowerShell terminal run:
    
    ```ps
    wsl --shutdown
    ```
    
1. Re-open WSL2

    Everything should be in place. Fire up WSL via the MS Terminal or just `wsl.exe`.
    You should be logged in as your normal user and `systemd` should be running
    
    You can test by running the following in WSL2:
    
    ```sh
    $ systemctl is-active dbus
    active
    ```

1. Create `/etc/rc.local` (optional)

    If you want to run certain commands when the WSL2 VM starts up, this is a useful file that's automatically ran by systemd.
    
    ```shell
    $ sudo touch /etc/rc.local
    $ sudo chmod +x /etc/rc.local
    $ sudo editor /etc/rc.local
    ```
    
    Add the following:
    ```sh
    #!/bin/sh -e
    
    # your commands here...
    
    exit 0
    ```

    `/etc/rc.local` is only run on "boot", so only when you first access WSL2 (or it's shutdown due to inactivity/no-processes).
    To test you can shutdown WSL via PowerShell/CMD `wsl --shutdown` then start it back up with `wsl`.

1. Fix-up `.profile`
    In ~/.profile, add to the end:
    ```sh
    # adds the WINPATH to the user's path if defined.
    if [ -n "$WINPATH" ]; then
        PATH="${PATH};${WINPATH}"
        export -n WINPATH
    fi
    ```

# Docker
1. Install Docker
    ```sh
    sudo apt-get update
    sudo apt-get install \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
    ```
1. Update Systemd and docker-daemon to listen on tcp
    * `/etc/docker/daemon.json`
    ```json
    {
      "hosts": [
        "tcp://0.0.0.0:2375",
        "unix:///var/run/docker.sock"
      ]
    }
    ```
    * `/etc/systemd/system/docker.service.d/override.conf`
    ```conf
    [Service]
    ExecStart=
    ExecStart=/usr/bin/dockerd
    ```
1. In windows, set the `DOCKER_HOST` env var to `tcp://localhost:2375`
1. Add a scheduled task to run on login:
    ```ps
    $job = start-job -ScriptBlock { c:\windows\system32\wsl.exe -d Ubuntu-20.04}
    $job | Wait-Job
    $job | Remove-Job
    ```
