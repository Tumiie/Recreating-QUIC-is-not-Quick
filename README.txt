This guide explains how to set up an OpenLiteSpeed QUIC-enabled HTTPS web server (Ubuntu VM) and a client machine (WSL Ubuntu) capable of performing HTTP/2 and HTTP/3 file download experiments. It includes installation steps for OpenLiteSpeed, QUIC/SSL configuration, and building a QUIC-enabled version of curl.

Requirements
Server: Ubuntu VM (bridged adapter recommended)
Client: Ubuntu on WSL (Windows 10/11)
Root or sudo access
Stable internet connection

1. SERVER SETUP (UBUNTU VM)
Install Required Packages

sudo apt update
sudo apt upgrade
sudo apt install -y build-essential git curl wget python3 python3-pip net-tools openssl \
libssl-dev iperf3 tcpdump htop sysstat iproute2 iputils-ping libpcre3-dev libexpat1-dev \
zlib1g-dev libxml2-dev libcurl4-openssl-dev
sudo apt install traceroute

Install OpenLiteSpeed
sudo wget -O - https://repo.litespeed.sh | sudo bash
sudo apt-get -y install openlitespeed
sudo apt-get install lsphp81 lsphp81-common lsphp81-mysql

Reminder: Add the OpenLiteSpeed admin password

sudo /usr/local/lsws/admin/misc/admpass.sh

After installing OpenLiteSpeed, QUIC must be enabled in the WebAdmin Console, not only in the config file. Follow the steps below:
1. Log in to the WebAdmin Console

Make sure the admin panel is running: sudo systemctl start lsws

Open your browser and go to: https://<server-ip>:7080

Log in with your admin username/password (created with admpass.sh).

2. Enable QUIC in Listeners (Port 443)
3. Map Listener to Virtual Host
4. Configure Virtual Host for HTTPS

Verify Installation
sudo systemctl status openlitespeed
/usr/local/lsws/bin/lshttpd -v

Start/stop OpenLiteSpeed:

sudo systemctl start lsws
sudo systemctl stop lsws

Enable HTTPS + QUIC
1. Generate SSL Certificates
sudo mkdir -p /usr/local/lsws/conf/cert
cd /usr/local/lsws/conf/cert
sudo openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem \
-days 365 -subj "/CN=lquic.local"

2. Update OpenLiteSpeed Configuration

Edit main config:

sudo nano /usr/local/lsws/conf/httpd_config.conf


Under listener, ensure:

listener Default {
    address                 *:443
    reusePort		    1
    secure                  1
    keyFile                 /usr/local/lsws/conf/cert/key.pem
    certFile                /usr/local/lsws/conf/cert/cert.pem
    sslProtocol		    16
    enableQuic              1
    enableSpdy              12
    map                     Example
}


Under virtual host:
vhRoot 		/usr/local/lsws/Example/html/
configFile	/usr/local/lsws/conf/vhosts/Example/vhconf.conf
quic		1
index  index.html


Restart to apply changes:sudo systemctl restart lsws

2. CLIENT SETUP (WSL UBUNTU)
Install Required Packages
sudo apt update
sudo apt upgrade
sudo apt install -y build-essential git curl clang libclang-dev python3 python3-pip net-tools \
iproute2 iperf3 tcpdump htop sysstat python3-matplotlib python3-pandas python3-scipy gnuplot jq \
cmake pkg-config libssl-dev libev-dev zlib1g-dev libnghttp2-dev libngtcp2-dev libnghttp3-dev \
autoconf libtool automake libpsl-dev
sudo apt install traceroute

Check curl version: curl -V
1. Build QUIC-TLS (quictls)
cd ~
git clone --depth 1 -b openssl-3.1.4+quic https://github.com/quictls/openssl
cd openssl
./config enable-tls1_3 --prefix=$HOME/opt/quictls --libdir=lib
make
sudo make install

2. Build nghttp3
cd ~
git clone https://github.com/ngtcp2/nghttp3
cd nghttp3
git submodule update --init
autoreconf -fi
./configure --prefix=$HOME/opt/nghttp3 --enable-lib-only
make
sudo make install
ls $HOME/opt/nghttp3/lib/pkgconfig/

Expected: libnghttp3.pc

3. Build ngtcp2
cd ~
git clone https://github.com/ngtcp2/ngtcp2
cd ngtcp2
make distclean || true
autoreconf -fi
./configure --prefix=$HOME/opt/ngtcp2 --enable-lib-only --with-openssl=$HOME/opt/quictls \
PKG_CONFIG_PATH=$HOME/opt/quictls/lib/pkgconfig:$HOME/opt/nghttp3/lib/pkgconfig \
LDFLAGS="-Wl,-rpath,$HOME/opt/quictls/lib"
make
sudo make install

Verify pkgconfig: ls $HOME/opt/ngtcp2/lib/pkgconfig


Export paths:

export PKG_CONFIG_PATH=$HOME/opt/ngtcp2/lib/pkgconfig:$HOME/opt/nghttp3/lib/pkgconfig:$HOME/opt/quictls/lib/pkgconfig
pkg-config --list-all | grep ngtcp2

4. Build quiche
cd ~
git clone --recursive https://github.com/cloudflare/quiche.git
cd quiche

export PKG_CONFIG_PATH="$HOME/opt/quictls/lib/pkgconfig:$PKG_CONFIG_PATH"

cargo build --release --features ffi,pkg-config-meta

mkdir -p deps/boringssl/src/lib
ln -s `find target/release -name libcrypto.a` deps/boringssl/src/lib/
ln -s `find target/release -name libssl.a` deps/boringssl/src/lib/
cd ..

5. Build Curl with HTTP/3
cd ~
git clone https://github.com/curl/curl
cd curl
autoreconf -fi

export QUICTLS_INSTALL_PATH="$HOME/opt/quictls"

./configure LDFLAGS="-Wl,-rpath,$HOME/quiche/target/release" --with-ssl="${QUICTLS_INSTALL_PATH}" --with-quiche="$HOME/quiche/target/release" --enable-alt-svc --enable-http3 
--with-nghttp3 --with-ngtcp2 --enable-websockets --disable-static --enable-shared PKG_CONFIG_PATH=$HOME/opt/ngtcp2/lib/pkgconfig:$HOME/opt/nghttp3/lib/pkgconfig:$HOME/opt/quictls/lib/pkgconfig 
--with-openssl=$HOME/opt/quictls --with-nghttp3=$HOME/opt/nghttp3 --with-ngtcp2=$HOME/opt/ngtcp2 --prefix=$HOME/opt/curl-quic
make
sudo make install
export PATH=$HOME/opt/curl-quic/bin:$PATH

Verify:
which curl
curl -V