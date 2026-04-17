# Nginx ModSecurity + GeoIP2 Dynamic Module Compiler

A robust compilation script that adds ModSecurity WAF and GeoIP2 country blocking capabilities to an existing Nginx installation without full recompilation.

## 🚀 Features

- **Dynamic Module Compilation**: Compiles ModSecurity and GeoIP2 as loadable modules—no need to replace your existing Nginx binary
- **OWASP CRS Integration**: Automatically sets up the OWASP Core Rule Set (v4.x)
- **GeoIP2 Country Blocking**: Native GeoIP2 support using MaxMind's `.mmdb` format
- **aaPanel Compatible**: Specifically designed for aaPanel Nginx installations
- **Preserves Existing Modules**: Retains all your current Nginx modules and configurations
- **Smart Patching**: Only adds module load directives if they don't already exist

## 📋 Prerequisites

- Nginx 1.20+ (tested with 1.29.4)
- Debian/Ubuntu-based system with `apt` package manager
- Existing aaPanel Nginx installation at `/www/server/nginx`
- Root/sudo access
- At least 2GB RAM for compilation

## 📦 Installation

### Quick Install
```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/compile-modsec-geoip.sh
chmod +x compile-modsec-geoip.sh
sudo ./compile-modsec-geoip.sh
```

### Step-by-Step Process

The script performs the following actions:

1. **Detects Nginx Version**: Automatically extracts your current Nginx version
2. **Installs Dependencies**: `libmaxminddb-dev` and other required libraries
3. **Builds ModSecurity**: Compiles the ModSecurity v3 engine from source
4. **Downloads Connectors**: Fetches ModSecurity-nginx and ngx_http_geoip2_module
5. **Compiles Dynamic Modules**: Builds `.so` files compatible with your Nginx version
6. **Patches nginx.conf**: Adds `load_module` directives automatically
7. **Sets Up OWASP CRS**: Downloads and configures the Core Rule Set
8. **Downloads GeoIP Database**: Fetches GeoLite2-Country.mmdb from a reliable mirror

## 🔧 Post-Installation Configuration

### Activating ModSecurity on a Website

Add these directives to your website's `server` block in aaPanel:

```nginx
server {
    # ... existing configuration ...
    
    modsecurity on;
    modsecurity_rules_file /www/server/nginx/conf/modsec/main.conf;
    
    # ... rest of configuration ...
}
```

### Configuring GeoIP2 Country Blocking

Add this to the `http` block in `/www/server/nginx/conf/nginx.conf`:

```nginx
http {
    # ... existing configuration ...
    
    # Load GeoIP2 database
    geoip2 /www/server/nginx/conf/GeoLite2-Country.mmdb {
        auto_reload 7d;
        $geoip2_country_code country iso_code;
    }
    
    # Define blocked countries
    map $geoip2_country_code $block_country {
        default 0;
        "CN" 1;  # China
        "RU" 1;  # Russia
        "KP" 1;  # North Korea
    }
    
    # ... rest of configuration ...
}
```

Then in your website's `server` block:

```nginx
server {
    # ... existing configuration ...
    
    if ($block_country = 1) {
        return 403;
    }
    
    # ... rest of configuration ...
}
```

### Updating the GeoIP Database

Create a monthly cron job to keep the database fresh:

```bash
# Add to crontab (crontab -e)
0 0 1 * * wget -q https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb -O /www/server/nginx/conf/GeoLite2-Country.mmdb && /www/server/nginx/sbin/nginx -s reload
```

## 📁 Directory Structure

```
/www/server/nginx/
├── conf/
│   ├── nginx.conf                    # Patched with load_module directives
│   ├── GeoLite2-Country.mmdb        # GeoIP database
│   └── modsec/                       # ModSecurity configuration
│       ├── main.conf                 # Main WAF configuration
│       ├── modsecurity.conf          # ModSecurity engine settings
│       ├── crs-setup.conf            # OWASP CRS setup
│       ├── unicode.mapping           # Unicode mapping file
│       └── coreruleset/              # OWASP CRS rules
│           └── rules/
│               ├── REQUEST-*.conf
│               └── ...
├── modules/
│   ├── ngx_http_modsecurity_module.so
│   └── ngx_http_geoip2_module.so
└── src/
    ├── ModSecurity/                  # ModSecurity source
    ├── ModSecurity-nginx/            # Nginx connector
    ├── ngx_http_geoip2_module/       # GeoIP2 module source
    └── nginx-{version}/              # Nginx source (temporary)
```

## ⚙️ Customization

### Modifying OWASP CRS Rules

Edit `/www/server/nginx/conf/modsec/crs-setup.conf` to:
- Adjust paranoia level (default: 1)
- Enable/disable specific rule categories
- Configure anomaly scoring thresholds

### Adding Custom ModSecurity Rules

Create `/www/server/nginx/conf/modsec/custom-rules.conf` and include it in `main.conf`:

```apache
# Whitelist your IP from all rules
SecRule REMOTE_ADDR "^192\.168\.1\.100$" "phase:1,id:1000,ctl:ruleEngine=Off"

# Block specific user agents
SecRule REQUEST_HEADERS:User-Agent "bad-bot" "id:1001,deny,status:403"
```

### Updating GeoIP Blocked Countries

Modify the `map $geoip2_country_code $block_country` section in `nginx.conf` to add/remove countries.

## 🔍 Verification

### Check Modules Are Loaded
```bash
/www/server/nginx/sbin/nginx -T 2>&1 | grep -E "modsecurity|geoip2"
```

### Test ModSecurity
```bash
curl -I "http://yoursite.com/?test=../../etc/passwd"
# Should return 403 Forbidden
```

### Test GeoIP Blocking
```bash
# Using a proxy from a blocked country
curl -x http://proxy-server:port http://yoursite.com/
# Should return 403 Forbidden
```

## 🐛 Troubleshooting

### "module not found" error
```bash
# Check if module files exist
ls -la /www/server/nginx/modules/

# Verify load_module paths in nginx.conf
grep load_module /www/server/nginx/conf/nginx.conf
```

### ModSecurity fails to load
```bash
# Check ModSecurity library
ldd /www/server/nginx/modules/ngx_http_modsecurity_module.so | grep "not found"

# Rebuild ModSecurity if needed
cd /www/server/nginx/src/ModSecurity
make clean && ./build.sh && ./configure && make && make install
ldconfig
```

### GeoIP2 module not working
```bash
# Verify database exists
ls -la /www/server/nginx/conf/GeoLite2-Country.mmdb

# Test database with mmdblookup
mmdblookup --file /www/server/nginx/conf/GeoLite2-Country.mmdb --ip 8.8.8.8 country iso_code
```

## 🔄 Updating

To update ModSecurity or OWASP CRS:

```bash
# Update ModSecurity
cd /www/server/nginx/src/ModSecurity
git pull
make clean && ./build.sh && ./configure && make && make install

# Update OWASP CRS
cd /www/server/nginx/conf/modsec/coreruleset
git pull

# Update GeoIP2 module
cd /www/server/nginx/src/ngx_http_geoip2_module
git pull

# Recompile modules
cd /www/server/nginx/src/nginx-$(/www/server/nginx/sbin/nginx -v 2>&1 | cut -d '/' -f 2)
make modules
cp objs/*.so /www/server/nginx/modules/
nginx -s reload
```

## 📝 License

This script is provided under the MIT License. See LICENSE file for details.

## 🙏 Credits

- [SpiderLabs/ModSecurity](https://github.com/SpiderLabs/ModSecurity)
- [owasp-modsecurity/ModSecurity-nginx](https://github.com/owasp-modsecurity/ModSecurity-nginx)
- [leev/ngx_http_geoip2_module](https://github.com/leev/ngx_http_geoip2_module)
- [coreruleset/coreruleset](https://github.com/coreruleset/coreruleset)
- [P3TERX/GeoLite.mmdb](https://github.com/P3TERX/GeoLite.mmdb) - GeoIP2 database mirror

## ⚠️ Disclaimer

This script compiles software from source and modifies your Nginx configuration. Always backup your existing Nginx installation before running. Test in a staging environment first.
