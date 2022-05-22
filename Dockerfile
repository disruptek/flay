FROM "alpine"
ARG ROCKS=luarocks-5.1

# sys reqs
RUN apk add luajit tar gzip unzip zlib luarocks5.1 openrc util-linux

# lua deps
RUN \
	apk add git make linux-headers openssl-dev lua-dev zlib-dev m4 gcc bsd-compat-headers musl-dev coreutils && \
	$ROCKS install lua-cjson && \
	$ROCKS install lua-zlib && \
	$ROCKS install luasocket && \
	$ROCKS install http && \
	apk del git make linux-headers openssl-dev lua-dev zlib-dev m4 gcc bsd-compat-headers musl-dev coreutils && \
	rm -rf /root/.cache

# console
RUN ln -s agetty /etc/init.d/agetty.ttyS0 && \
	echo ttyS0 > /etc/securetty && \
	rc-update add agetty.ttyS0 default

# i guess
RUN rc-update add devfs boot && \
	rc-update add procfs boot && \
	rc-update add sysfs boot

COPY --chmod=644 fennel.lua /fennel.lua
COPY --chmod=755 server.lua /server.lua

ENV PATH=/usr/sbin:/usr/bin:/sbin:/bin
ENV LUA_PATH=/usr/local/share/lua/5.1/?.lua;/usr/lib/lua/5.1/?.lua;;
ENV LUA_CPATH=/usr/local/lib/lua/5.1/?.so;/usr/lib/lua/5.1/?.so;;
WORKDIR "/"
ENTRYPOINT ["/server.lua"]
