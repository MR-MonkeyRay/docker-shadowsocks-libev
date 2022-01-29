FROM alpine:3.15
LABEL maintainer="MonkeyRay <mr.monkeyray@gmail.com>"

WORKDIR /tmp

# Install deps
RUN apk add --no-cache --virtual .build-deps \
    autoconf \
    automake \
    build-base \
    c-ares-dev \
    libcap \
    libev-dev \
    libtool \
    libsodium-dev \
    linux-headers \
    mbedtls-dev \
    pcre-dev \
    git \
# Clone shadowsocks-libev git repo
&&  git clone --recurse-submodules -j3 https://github.com/shadowsocks/shadowsocks-libev.git /tmp/repo \
# Build shadowsocks-libev
&&  cd /tmp/repo \
&&  ./autogen.sh \
&&  ./configure --prefix=/usr --disable-documentation \
&&  make install \
&&  ls /usr/bin/ss-* | xargs -n1 setcap cap_net_bind_service+ep \
&&  apk del .build-deps \
# Runtime dependencies setup
&&  apk add --no-cache \
    ca-certificates \
    rng-tools \
    tzdata \
    $(scanelf --needed --nobanner /usr/bin/ss-* \
    | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
    | sort -u) \
&&  rm -rf /tmp/repo

# Set xray-plugin version
ARG XRAY_PLUGIN_VERSION=latest

# Get xray-plugin
RUN apk add --no-cache jq curl \
&&  if [[ "${XRAY_PLUGIN_VERSION}" == "latest" ]]; then \
        xray_release=$(curl -s https://api.github.com/repos/teddysun/xray-plugin/releases/latest); \
    else \
        xray_release=$(curl -s https://api.github.com/repos/teddysun/xray-plugin/releases/tags/${XRAY_PLUGIN_VERSION}); \
    fi \
# Count the number of assets in this release
&&  assets=$(echo "$xray_release" | jq -r '.assets | length') \
# Iterate through each of the assets and see if the name of the asset matches what we're looking for
&&  for i in $(seq $assets $END); do \
        if echo "$xray_release" | jq -r ".assets["$(($i - 1))"].name" | grep "xray-plugin-linux-amd64"; then \
            download_link=$(echo "$xray_release" | jq -r ".assets["$(($i - 1))"].browser_download_url"); \
            break; \
        fi \
    done \
&&  download_link=$(echo "${xray_release}" | jq -r ".assets["$(($i - 1))"].browser_download_url") \
# Check if download_link variable
&&  if [ -z "${download_link}" ]; then \
        echo "Error when geting xray plugin download link! Url got: '${download_link}'"; \
        exit 1; \
    fi \
&&  curl -L ${download_link} -o /tmp/xray-plugin.tar.gz \
&&  tar zxf /tmp/xray-plugin.tar.gz \
&&  mv /tmp/xray-plugin_linux_amd64 /usr/local/bin/xray-plugin \
&&  apk del jq curl

# Shadowsocks environment variables
ENV SERVER_PORT=6443 \
    PASSWORD="RdWfMU7CbKTKeJiW" \
    METHOD="chacha20-ietf-poly1305" \
    TIMEOUT=1800 \
    DNS_ADDRS="8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844" \
    ARGS="-u"

# Expose port
EXPOSE ${SERVER_PORT}

# Run as nobody
USER nobody

# Start shadowsocks-libev server with xray-plugin
CMD ss-server \
    -s 0.0.0.0 \
    -s ::0 \
    -p $SERVER_PORT \
    -k $PASSWORD \
    -m $METHOD \
    -t $TIMEOUT \
    -d $DNS_ADDRS \
    --reuse-port \
    --no-delay \
    --plugin xray-plugin \
    $ARGS