#!/bin/bash

set -e # exits when errored

readonly CYAN='\033[0;36m'
readonly RED='\033[0;31m'
readonly RST='\033[0m'
readonly GREEN="\033[0;32m"

readonly JSON_PATH='/etc/v2ray' # config path
# https://www.v2fly.org/en_US/guide/install.html#docker

readonly CADDY_PATH=$(which caddy)

# ssl
mkdir /etc/ssl/caddy
chmod 0770 /etc/ssl/caddy
echo -e "${CYAN}SSL certificates will be stored at /etc/ssl/caddy${RST}"

# v2ray config
echo "Setting up configuration for v2ray..."

function port0 {
  echo $(comm -23 <(seq 49152 65535 | sort) <(ss -Htan | awk '{print $4}' | cut -d':' -f2 | sort -u) | shuf | head -n 1)
  # https://unix.stackexchange.com/questions/55913/whats-the-easiest-way-to-find-an-unused-local-port
}

read -e -p "$(echo -e "${RED}*${RST}") Enter the webSocket pathname: " -i "/$RANDOM.m3u8" VAR_WS_PATH
read -e -p "$(echo -e "${RED}*${RST}") Enter the port to be listened: " -i "$(port0)" VAR_PORT
read -e -p "- Enter the log storage location: " -i "/var/log/v2ray" VAR_LOG_PATH
read -e -p "- Enter the alter id (see v2ray issues/518): " -i "$(($RANDOM % 255))" VAR_ALTER_ID
read -e -p "- Enter the uuid: " -i "$(uuidgen)" VAR_UUID

echo -e "${CYAN}V2ray config path: ${JSON_PATH}${RST}"
chmod 666 ${JSON_PATH}/config.json

cat >${JSON_PATH}/config.json <<EOF
{
  "outbound": {
    "protocol": "freedom"
  },
  "log": {
    "access": "${VAR_LOG_PATH}/access.log",
    "loglevel": "info",
    "error": "${VAR_LOG_PATH}/error.log"
  },
  "outboundDetour": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ],
  "inbound": {
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "${VAR_WS_PATH}"
      }
    },
    "settings": {
      "udp": true,
      "clients": [
        {
          "alterId": ${VAR_ALTER_ID},
          "security": "auto",
          "id": "${VAR_UUID}"
        }
      ]
    },
    "protocol": "vmess",
    "port": ${VAR_PORT},
    "listen": "localhost"
  },
  "routing": {
    "settings": {
      "rules": [
        {
          "ip": [
            "0.0.0.0/8",
            "10.0.0.0/8",
            "100.64.0.0/10",
            "127.0.0.0/8",
            "169.254.0.0/16",
            "172.16.0.0/12",
            "192.0.0.0/24",
            "192.0.2.0/24",
            "192.168.0.0/16",
            "198.18.0.0/15",
            "198.51.100.0/24",
            "203.0.113.0/24",
            "::1/128",
            "fc00::/7",
            "fe80::/10"
          ],
          "type": "field",
          "outboundTag": "blocked"
        }
      ]
    },
    "strategy": "rules"
  }
}
EOF
echo -e "${CYAN}Testing...${RST}"
v2ray -test -config ${JSON_PATH}/config.json
echo -e "${CYAN}Test done.${RST}"
read -e -p "$(echo -e "${RED}*${RST}") Your domain name: " -i "localhost" VAR_DOMAIN

# static files
mkdir -p /var/www/${VAR_DOMAIN}
echo '<h1>Hello World!</h1>' | tee /var/www/${VAR_DOMAIN}/index.html
echo -e "${CYAN}Created static files folder at /var/www/${VAR_DOMAIN}${RST}"

# Caddyfile
readonly CADDY_FILE_PATH="/etc/caddy"

readonly PASSWORD=$(uuidgen)
# readonly PASSWD_HASHED=$(htpasswd -bnBC 10 "" "${PASSWORD}" | tr -d ':\n')
# readonly PASSWD_HASHED_BASE64=$(echo "${PASSWD_HASHED}" | base64)
readonly PASSWD_HASHED_BASE64=$(caddy hash-password --plaintext "$PASSWORD")

echo $PASSWORD
echo $PASSWD_HASHED
echo $PASSWD_HASHED_BASE64

cat >${CADDY_FILE_PATH}/Caddyfile <<EOF
${VAR_DOMAIN} {
	root * /var/www/${VAR_DOMAIN}
	encode gzip
  file_server
	route {
    reverse_proxy ${VAR_WS_PATH} http://localhost:${VAR_PORT} 

    redir /config /config/

    route /config/* {
      basicauth bcrypt {
        clash ${PASSWD_HASHED_BASE64}
      }
    }

    route /config/ {
      file_server browse
    }

    route /config/*.yaml {
      header {
        Content-Disposition "attachment; filename={http.auth.user.id}-config.yaml"
        Content-Type application/x-yaml
      }
    }
  }
}

handle_errors {
	respond "{http.error.status_code} {http.error.status_text}"
}
EOF

echo -e "${CYAN}Caddyfile path: ${CADDY_FILE_PATH}/Caddyfile${RST}"
echo -e "${CYAN}Testing...${RST}"
caddy validate -config ${CADDY_FILE_PATH}/Caddyfile
echo -e "${CYAN}Test done.${RST}"

mkdir /var/www/${VAR_DOMAIN}/config
cat >/var/www/${VAR_DOMAIN}/config/clash.yaml<< EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: Rule
log-level: info
external-controller: 127.0.0.1:9090
proxies:
  - name: "TLS-WS-VMESS"
    type: vmess
    port: 443
    uuid: ${VAR_UUID}
    alterId: ${VAR_ALTER_ID}
    cipher: auto
    udp: true
    tls: true
    server: ${VAR_DOMAIN}
    servername: ${VAR_DOMAIN}
    network: ws
    ws-path: ${VAR_WS_PATH}
    ws-headers:
      Host: ${VAR_DOMAIN}
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - DIRECT
      - TLS-WS-VMESS
rules:
  - MATCH,Proxy
dns:
  enable: true
  listen: :53
  enhanced-mode: redir-host
  nameserver:
    - 114.114.114.114
    - 223.5.5.5
    - tls://dns.rubyfish.cn:853
  fallback:
    - 8.8.8.8
    - tls://1.1.1.1:853
    - tcp://1.1.1.1:53
    - tcp://208.67.222.222:443
    - tls://dns.google
    - https://1.1.1.1/dns-query
  fallback-filter:
    geoip: true
    ipcidr:
      - 240.0.0.0/4
EOF

nohup caddy run --config ${CADDY_FILE_PATH}/Caddyfile --adapter caddyfile &

echo --------
echo -e "${GREEN}USER:   clash${RST}"
echo -e "${GREEN}PASSWD: ${PASSWORD}${RST}"
echo -e "${CYAN}Config files is available at https://${VAR_DOMAIN}/config/ ${RST}"
echo "(For deletion, do 'rm -rf /var/www/${VAR_DOMAIN}/config')"
echo --------

v2ray -config ${JSON_PATH}/config.json >/dev/null