#!/bin/bash

# Configuration Paths
NGINX_SRC="/www/server/nginx/src"
NGINX_VER=$(/www/server/nginx/sbin/nginx -v 2>&1 | cut -d '/' -f 2 | cut -d ' ' -f 1)
MODSEC_DIR="$NGINX_SRC/ModSecurity"
MODSEC_NGINX="$NGINX_SRC/ModSecurity-nginx"
GEOIP2_SRC="$NGINX_SRC/ngx_http_geoip2_module"
CONF_DIR="/www/server/nginx/conf/modsec"
NGINX_CONF="/www/server/nginx/conf/nginx.conf"
NGINX_MODULE="/www/server/nginx/modules"

echo "Detected Nginx Version: $NGINX_VER"
echo "Deleting pre-version config settings"

rm -rf $NGINX_SRC
rm -rf $CONF_DIR
rm -rf $NGINX_MODULE

# INSTALL DEPENDENCIES
echo "--- 1. Installing Dependencies ---"
apt update && apt install -y libmaxminddb-dev libpcre2-dev #apt-utils autoconf automake build-essential git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre++-dev libtool libxml2-dev libyajl-dev pkgconf wget zlib1g-dev libjemalloc-dev

echo "--- 2. Building ModSecurity Engine ---"
mkdir -p $NGINX_SRC
cd $NGINX_SRC
if [ ! -d "$MODSEC_DIR" ]; then
    git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity
fi
cd ModSecurity
# FIXED: Use --init --recursive to get nested submodules like mbedtls
git submodule update --init --recursive
./build.sh && ./configure && make -j$(nproc) && make install

echo "--- 3. Preparing Nginx Connector & Source ---"
cd $NGINX_SRC
# Download WAF Connector
[ ! -d "$MODSEC_NGINX" ] && git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git
# Download GeoIP2 Module
[ ! -d "$GEOIP2_SRC" ] && git clone --depth 1 https://github.com/leev/ngx_http_geoip2_module.git
# Download ALL required third-party modules
echo "Downloading required third-party modules..."
[ ! -d "ngx_devel_kit" ] && git clone --depth 1 https://github.com/vision5/ngx_devel_kit.git
[ ! -d "lua_nginx_module" ] && git clone --depth 1 https://github.com/openresty/lua-nginx-module.git lua_nginx_module
[ ! -d "ngx_cache_purge" ] && git clone --depth 1 https://github.com/FRiCKLE/ngx_cache_purge.git
[ ! -d "ngx_http_substitutions_filter_module-master" ] && git clone --depth 1 https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git ngx_http_substitutions_filter_module-master
[ ! -d "nginx-dav-ext-module" ] && git clone --depth 1 https://github.com/arut/nginx-dav-ext-module.git

# Verify all required modules exist
echo "Verifying required modules..."
MISSING_MODULES=0
for dir in ngx_devel_kit lua_nginx_module ngx_cache_purge ngx_http_substitutions_filter_module-master nginx-dav-ext-module ModSecurity-nginx ngx_http_geoip2_module; do
    if [ -f "$dir/config" ]; then
        echo "  ✓ $dir"
    else
        echo "  ✗ $dir - MISSING or incomplete"
        MISSING_MODULES=1
    fi
done

if [ $MISSING_MODULES -eq 1 ]; then
    echo "FATAL: Some required modules are missing. Please check the errors above."
    exit 1
fi
echo "All modules verified successfully"

# Download and extract Nginx source
rm -rf nginx-$NGINX_VER
wget -qO- https://nginx.org/download/nginx-$NGINX_VER.tar.gz | tar xz
cd nginx-$NGINX_VER

echo "--- 4. Compiling Dynamic Module ---"
export LUAJIT_LIB=/usr/local/lib
export LUAJIT_INC=/usr/local/include/luajit-2.1

# Make absolutely sure we're in the Nginx source directory
cd $NGINX_SRC/nginx-$NGINX_VER || {
    echo "FATAL: Cannot enter Nginx source directory"
    exit 1
}
echo "Current directory: $(pwd)"

./configure --user=www --group=www --prefix=/www/server/nginx \
--add-module=$NGINX_SRC/ngx_devel_kit \
--add-module=$NGINX_SRC/lua_nginx_module \
--add-module=$NGINX_SRC/ngx_cache_purge \
--with-pcre \
--with-pcre-jit \
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

# Check if configure succeeded
if [ $? -ne 0 ]; then
    echo "FATAL: ./configure failed"
    exit 1
fi

echo "Running make modules..."
make modules

# Check if make succeeded
if [ $? -ne 0 ]; then
    echo "FATAL: make modules failed"
    exit 1
fi

# Verify .so files were created
echo "Checking for compiled modules..."
ls -la objs/*.so

mkdir -p /www/server/nginx/modules
cp objs/ngx_http_modsecurity_module.so /www/server/nginx/modules/ && echo "Copied modsecurity module" || echo "FAILED to copy modsecurity module"
cp objs/ngx_http_geoip2_module.so /www/server/nginx/modules/ && echo "Copied geoip2 module" || echo "FAILED to copy geoip2 module"

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
