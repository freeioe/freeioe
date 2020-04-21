# Build Tips

For the people who wants to build run FreeIOE in your own PC

## Pull code

Pull repos:

``` sh
git clone https://github.com/freeioe/skynet.git
git clone https://github.com/freeioe/freeioe.git
git clone https://github.com/kooiot/lwf.git
```

### Prepare submodules (skynet)

``` sh
cd skynet
git submodule init
git submodule update

cd 3rd/lua-mosquitto
git submodule init
git submodule update

```

### Prepare freeioe example apps/prebuilt

``` sh
cd freeioe
mkdir apps
mkdir ext
./scripts/feeds update -a
cd apps
ln -s ../feeds/example_apps/ioe ./
```

TIPS:

<B> Before run the ./scripts/feeds update -a </B>

<i>
Edit the feeds.conf.default file
Remove the first comments on first two lines
Comment the 3,4 lines
Then run the ./scripts/feeds update -a
</i>

### Prepare submodules (lwf)

``` sh
cd lwf
git submodule init
git submodule update
```


## Prepare your build env

### Ubuntu/Debian:

``` sh
sudo apt install binutils
sudo apt install autoconf
sudo apt install libssl-dev
sudo apt install libcurl4-openssl-dev
sudo apt install libenet-dev
sudo apt install libmodbus-dev
```

## Make

``` sh
cd skynet
make linux
```

## Run

### Link FreeIOE to skynet folder

``` sh
cd skynet
ln -s ../freeioe ./ioe
```

### Correct the lwf links

``` sh
cd freeioe/lualib
rm lwf
rm lwf.lua
rm resty
ln -s ../../lwf/lwf ./lwf
ln -s ../../lwf/lwf.lua ./lwf.lua
ln -s ../../lwf/resty ./resty
```

### Run skynet

``` sh
cd skynet
./skynet ioe/config
```


### Issues



