# NetMon.lua
A NetworkManager GObject based network monitor without a Desktop Environment

### Features

- Automatic Network monitoring (Wifi, Ethernet and Even Access-Point Hotspots)
- Debugging info (When $CHECKNET_DEBUG is set in the environment) -- Use `journalctl -f` for even more info
- basic Logging to a specified file (WIP: logs still look ugly and unorganized)

### Instalation instructions:

first dependency is, of course, Lua (preferably the newest version)
If you are on Arch, run:

    # pacman -Sy lua luarocks lua-lgi

On other distributions, it's best to compile lua yourself:

```bash
curl -L -R -O https://www.lua.org/ftp/lua-5.4.6.tar.gz
tar zxf lua-5.4.6.tar.gz
cd lua-5.4.6
make all test

make install # as root
```

Then clone this repo with:

    $ git clone --recurse-submodules https://github.com/TsukiGva2/NetMon.lua

to fetch the debugging module, then you can simply run make as root:

    # luarocks make
