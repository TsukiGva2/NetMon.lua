# NetMon.lua
A NetworkManager GObject based network monitor without a Desktop Environment

### Features

- Automatic Network monitoring (Wifi, Ethernet and Even Access-Point Hotspots)
- Debugging info (When $CHECKNET_DEBUG is set in the environment) -- Use `journalctl -f` for even more info
- basic Logging to a specified file (WIP: logs still look ugly and unorganized)

### Instalation instructions:

### Lua and Luarocks
first dependency is, of course, Lua (preferably the newest version)
If you are on Arch, run:

    # pacman -Sy lua luarocks

On other distributions, it's best to compile lua yourself:

```bash
curl -L -R -O https://www.lua.org/ftp/lua-5.4.6.tar.gz
tar zxf lua-5.4.6.tar.gz
cd lua-5.4.6
make all test

make install # as root
```

And then do the same for luarocks:
```bash
curl -L -R -O http://luarocks.github.io/luarocks/releases/luarocks-3.11.1.tar.gz
tar zxf luarocks-3.11.1.tar.gz
cd luarocks-3.11.1
make
make install # as root
```
if you get any errors, refer to: https://github.com/luarocks/luarocks/wiki/Installation-instructions-for-Unix

### Lgi

again, if you are on Arch you can simply do:

    pacman -Sy lua-lgi

You can look through their documentation at [lgi](https://github.com/lgi-devs/lgi),
but i recommend installing the latest version using the command:

    luarocks install https://raw.githubusercontent.com/lgi-devs/lgi/master/lgi-scm-1.rockspec

from lgi-devs/lgi#305

### Running NetMon.lua

Then clone this repo with:

    $ git clone --recurse-submodules https://github.com/TsukiGva2/NetMon.lua

to fetch the debugging module, then you can simply run make as root:

    # luarocks make

Now run the script with

    $ netmon
