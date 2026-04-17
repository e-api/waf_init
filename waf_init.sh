#!/bin/bash

# Configuration Paths
NGINX_SRC="/www/server/nginx/src"
NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1 | cut -d '/' -f 2 | cut -d ' ' -f 1)
MODSEC_DIR="$NGINX_SRC/ModSecurity"
MODSEC_NGINX="$NGINX_SRC/ModSecurity-nginx"
GEOIP2_SRC="$NGINX_SRC/ngx_http_geoip2_module"
CONF_DIR="/www/server/nginx/conf/modsec"
NGINX_CONF="/www/server/nginx/conf/nginx.conf"

echo "Detected Nginx Version: $NGINX_VER"

# INSTALL DEPENDENCIES
echo "--- 1. Installing Dependencies ---"
apt update && apt install -y libmaxminddb-dev # apt-utils autoconf automake build-essential git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre++-dev libtool libxml2-dev libyajl-dev pkgconf wget zlib1g-dev libjemalloc-dev

echo "--- 2. Building ModSecurity Engine ---"
cd $NGINX_SRC
if [ ! -d "$MODSEC_DIR" ]; then
    git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
fi
cd ModSecurity
git submodule init && git submodule update
./build.sh && ./configure && make -j$(nproc) && make install

echo "--- 3. Preparing Nginx Connector & Source ---"
cd $NGINX_SRC
# Download WAF Connector
[ ! -d "$MODSEC_NGINX" ] && git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git
# Download GeoIP2 Module
[ ! -d "$GEOIP2_SRC" ] && git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git

rm -rf nginx-$NGINX_VER
wget -qO- https://nginx.org/download/nginx-$NGINX_VER.tar.gz | tar xz
cd nginx-$NGINX_VER

# Links for aaPanel library structure
if [ -d "$NGINX_SRC/pcre-8.43" ]; then
    ln -sf $NGINX_SRC/pcre-8.43 pcre-8.43
else
    echo "Error: PCRE source not found in $NGINX_SRC" && exit 1
fi

echo "--- 4. Compiling Dynamic Module ---"
export LUAJIT_LIB=/usr/local/lib
export LUAJIT_INC=/usr/local/include/luajit-2.1

./configure --user=www --group=www --prefix=/www/server/nginx \
--add-module=$NGINX_SRC/ngx_devel_kit \
--add-module=$NGINX_SRC/lua_nginx_module \
--add-module=$NGINX_SRC/ngx_cache_purge \
--add-module=$NGINX_SRC/nginx-sticky-module-ng-1.3.0 \
--with-openssl=$NGINX_SRC/openssl \
--with-pcre=pcre-8.43 \
--with-http_v2_module --with-stream --with-stream_ssl_module --with-stream_ssl_preread_module \
--with-http_stub_status_module --with-http_ssl_module --with-http_image_filter_module \
--with-http_gzip_static_module --with-http_gunzip_module --with-http_sub_module \
--with-http_flv_module --with-http_addition_module --with-http_realip_module \
--with-http_mp4_module --with-http_auth_request_module \
--add-module=$NGINX_SRC/ngx_http_substitutions_filter_module-master \
--with-ld-opt="-Wl,-E -ljemalloc" --with-cc-opt="-Wno-error" \
--with-http_dav_module --add-module=$NGINX_SRC/nginx-dav-ext-module \
--with-http_v3_module \
--add-dynamic-module=$MODSEC_NGINX \
--add-dynamic-module=$GEOIP2_SRC

make modules
mkdir -p /www/server/nginx/modules
cp objs/ngx_http_modsecurity_module.so /www/server/nginx/modules/
cp objs/ngx_http_geoip2_module.so /www/server/nginx/modules/

echo "--- 5. Patching nginx.conf ---"
grep -q "ngx_http_modsecurity_module.so" "$NGINX_CONF" && echo "load_module modSecurity already exists in $NGINX_CONF" || { sed -i '1i load_module modules/ngx_http_modsecurity_module.so;' "$NGINX_CONF"; echo "Added load_module modSecurity to $NGINX_CONF"; }
grep -q "ngx_http_geoip2_module.so" "$NGINX_CONF" && echo "load_module geoIP already exists in $NGINX_CONF" || { sed -i '1i load_module modules/ngx_http_geoip2_module.so;' "$NGINX_CONF"; echo "Added load_module geoIP to $NGINX_CONF"; }

echo "--- 6. Setting up OWASP CRS ---"
mkdir -p $CONF_DIR
cp $MODSEC_DIR/modsecurity.conf-recommended $CONF_DIR/modsecurity.conf
cp $MODSEC_DIR/unicode.mapping $CONF_DIR/
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' $CONF_DIR/modsecurity.conf

cd $CONF_DIR
if [ ! -d "coreruleset" ]; then
    git clone https://github.com/coreruleset/coreruleset
fi
cp coreruleset/crs-setup.conf.example crs-setup.conf

cat <<EOF > main.conf
Include $CONF_DIR/modsecurity.conf
Include $CONF_DIR/crs-setup.conf
Include $CONF_DIR/coreruleset/rules/*.conf
# Access/HTTP3 Fixes
SecRuleRemoveById 920280
EOF

echo "--- Done! ---"
echo "Module compiled and loaded in $NGINX_CONF"
echo "To activate, add these lines to your Website config in aaPanel:"
echo "modsecurity on;"
echo "modsecurity_rules_file $CONF_DIR/main.conf;"
echo "Downloading GeoLite2-Country.mmdb to /www/server/nginx/conf/"
wget https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb -O /www/server/nginx/conf/GeoLite2-Country.mmdb
echo "Restarting Nginx to apply changes."

/www/server/nginx/sbin/nginx -t

echo "Don't forget to add your GeoIP map logic to the 'http' block in nginx.conf and 'server' block at your site"
