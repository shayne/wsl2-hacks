# wsl2-hacks - Updated for Ubuntu 20.04 / 20.10
Useful snippets / tools for using WSL2 as a development environment
Updated based on issue #7 guidance from '@scotte' and '@JohnTasto'
---

**Auto-start/services** (`systemd` and `snap` support)

I've done a few methods that have had various levels of success. My goal was to make it feel seamless for my workflow and have commands work as expected. What's below is the current version of the setup I use. It allows me to use the MS Terminal as well as VSCode's Remote WSL plugin.

With this setup your shells will be able to run `systemctl` commands, have auto-starting services, as well as be able to run [snaps](https://tutorials.ubuntu.com/tutorial/basic-snap-usage).

1. Install deps

    ```shell
    $ sudo apt update
    $ sudo apt install dbus policykit-1 daemonize
    ```

2. Create a fake-`bash`

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
    UNAME="<YOURUSER>"

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
    
    # enter systemd namespace
    exec /usr/bin/nsenter -t "${SYSTEMD_PID}" -m -p --wd="${PWD}" /sbin/runuser $RUNOPTS -s "${USHELL}" "${UNAME}" -- "${@}"
    ```

3. Set the fake-`bash` as our `root` user's shell

    We need `root` level permission to get `systemd` setup and enter the environment. The way I went about solving this is to
    have WSL2 default to the `root` user and when `wsl.exe` is executed the fake-`bash` will do the right thing.
    
    The next step in getting this working is to change the default shell for our `root` user.
    
    Edit the `/etc/passwd` file:
    
    `$ vipw`
    
    `$ vipw -s`
    
    Find the line starting with `root:`, it should be the first line.
    Add a line:
    
    `rootwsl:x:0:0:root:/root:/usr/local/bin/wsl2hack`
    
    *Never replace `/usr/bin/bash` as it is an actual binary in Ubuntu 20.04/20.10*
    
    Save and close this file.
    
    Make sure to update the primary passwd file *and* the shadow passwd file.

4. Exit out of / close the WSL2 shell

    The next step is to shutdown WSL2 and to change the default user to `root`.

    In a PowerShell terminal run:
    
    ```
    > wsl --shutdown
    > ubuntu config --default-user root
    ```
    
5. Re-open WSL2

    Everything should be in place. Fire up WSL via the MS Terminal or just `wsl.exe`.
    You should be logged in as your normal user and `systemd` should be running
    
    You can test by running the following in WSL2:
    
    ```sh
    $ systemctl is-active dbus
    active
    ```

6. Create `/etc/rc.local` (optional)

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

---

**Access localhost ports from Windows**

**NOTE: No longer needed as of build 18945**

Many development servers default to binding to `127.0.0.1` or `localhost`. It can be cumbersome and frustrating to get it to bind to `0.0.0.0` to make it accessible via Windows using the IP of the WSL2 VM.

> Take a look at https://github.com/shayne/go-wsl2-host to have `wsl.local` automatically resolve to the WSL2 VM

To make these dev servers / ports accessible you can run the following commands, or add them to the `/etc/rc.local` if you have `systemd` running:

```shell
# /etc/rc.local runs as root by default
# if you run these yourself add 'sudo' to the beginning of each command

$ sysctl -w net.ipv4.conf.all.route_localnet=1
$ iptables -t nat -I PREROUTING -p tcp -j DNAT --to-destination 127.0.0.1 
```

---

**Increase `max_user_watches`**

If devtools are watching for file changes, the default is too low.

```
# /etc/rc.local runs as root by default
# if you run these yourself add 'sudo' to the beginning of each command

sysctl -w fs.inotify.max_user_watches=524288
```

---

**Open MS Terminal to home directory by default**

Open your MS Terminal configuration <kbd>Ctrl+,</kbd>

Find the `"commandLine":...` config for the WSL profile.

Change to something like:

```json
"commandline": "wsl.exe ~ -d Ubuntu-18.04",
```


**Copy current IP of WSL2 into Windows clipboard** (optionally with port 3000 here):

```
hostname -I | awk '{print $1}' | awk '{printf "%s:3000", $0}' | clip.exe
```

Alternatively, put it in a file, for example `copy_ip.sh`, make it executable with `chmod +x copy_ip.sh` and you can get the IP any time with `./copy_ip.sh`: 

```
#!/bin/bash
hostname -I | awk '{print $1}' | awk '{printf "%s:3000", $0}' | clip.exe
```
