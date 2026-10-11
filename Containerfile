# ==============================================================================
# STAGE 1: Gather Pure Statically-Compiled Binaries
# ==============================================================================
FROM alpine:3.21 AS builder

# Install curl, tar, xz (for Zig unpacking) and busybox-static
RUN apk add --no-cache curl tar xz busybox-static ca-certificates git

WORKDIR /staging
RUN useradd developer
# 1. Download and extract the official STATIC release of Zig 0.17.0
# (This logic dynamically targets x86_64 or aarch64 based on your host CPU)
RUN ARCH=$(uname -m) && \
    curl -sSL "ziglang.org/download/0.17.0/zig-$ARCH-linux-0.17.0.tar.xz" | tar -xJ --strip-components=1

# 2. Build staging directories for the final scratch environment
RUN mkdir -p /extracted/bin /extracted/lib

# 3. Move the pure static Zig binary and its standard library assets
RUN cp zig /extracted/bin/zig && \
    cp -r lib/* /extracted/lib/

# 4. FIXED: Copy Alpine's native, 100% static busybox binary directly from the host system layer
RUN cp /bin/busybox.static /extracted/bin/busybox
RUN mkdir -p /extracted/etc/ssl/certs
RUN cp /etc/ssl/certs/ca-certificates.crt /extracted/etc/ssl/certs/ca-certificates.crt
RUN curl -O https://codeberg.org/neurocyte/flow/releases/download/v0.7.2/flow-v0.7.2-linux-$(uname -m).tar.gz
RUN tar xzf flow-v0.7.2-linux-$(uname -m).tar.gz
RUN cp flow /extracted/bin/flow
# 5. Make the main busybox binary executable, then generate the 'sh' and tool links
RUN chmod +x /extracted/bin/busybox && \
    ln -s busybox /extracted/bin/sh && \
    ln -s busybox /extracted/bin/ls && \
    ln -s busybox /extracted/bin/cat && \
    ln -s busybox /extracted/bin/mkdir
# 5. Bring over Git, its sub-executables, the musl runtime, and its missing shared libraries
# 5. Bring over Git, its sub-executables, the musl runtime, and its missing shared libraries
# 5. Bring over Git, runtime, libcurl, SSL dependencies, protocols, and templates
# 5. Bring over Git, runtime, libcurl + its 6 downstream dependencies, SSL, protocols, and templates
RUN mkdir -p /extracted/bin /extracted/lib /extracted/usr/lib /extracted/usr/libexec /extracted/usr/share/git-core /extracted/etc && \
    cp /usr/bin/git /extracted/bin/ && \
    cp /lib/ld-musl-*.so.1 /extracted/lib/ && \
    # THE COMPLETE LIBCURL DEPENDENCY MATRIX:
    cp /usr/lib/libz.so.1 \
       /usr/lib/libpcre2-8.so.0 \
       /usr/lib/libcurl.so.4 \
       /usr/lib/libcrypto.so.3 \
       /usr/lib/libssl.so.3 \
       /usr/lib/libcares.so.2 \
       /usr/lib/libnghttp2.so.14 \
       /usr/lib/libidn2.so.0 \
       /usr/lib/libpsl.so.5 \
       /usr/lib/libzstd.so.1 \
       /usr/lib/libbrotlidec.so.1 \
       /extracted/usr/lib/ && \
    # Include fallback compression layer which brotlidec depends on internally
    cp /usr/lib/libbrotlicommon.so.1 /extracted/usr/lib/ && \
    # Include localization/domain dependencies for libidn2
    cp /usr/lib/libunistring.so.5 /extracted/usr/lib/ && \
    cp /etc/passwd /etc/protocols /extracted/etc/ && \
    cp -r /usr/libexec/git-core /extracted/usr/libexec/ && \
    cp -r /usr/share/git-core/templates /extracted/usr/share/git-core/

RUN cd /extracted/etc/ssl && ln -s certs/ca-certificates.crt cert.pem
# ==============================================================================
# STAGE 2: The Final True "FROM scratch" Container
# ==============================================================================
FROM scratch

# Bring over only the static binaries and the Zig library
COPY --from=builder /extracted/ /
# Provide basic PATH settings so running 'zig' works out of the box
ENV PATH=/bin:/usr/bin
ENV ZIG_GLOBAL_CACHE_DIR=/tmp
RUN mkdir -p /home/developer
USER developer
# Drop straight into your custom standalone shell prompt!
CMD ["/bin/sh"]
