# ==============================================================================
# STAGE 1: Gather Pure Statically-Compiled Binaries
# ==============================================================================
FROM alpine:3.21 AS builder

# Install curl, tar, xz (for Zig unpacking) and busybox-static
RUN apk add --no-cache curl tar xz busybox-static ca-certificates git

WORKDIR /staging

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
RUN mkdir -p /extracted/bin /extracted/lib /extracted/usr/lib /extracted/usr/libexec /extracted/etc && \
    # Copy the main git binary
    cp /usr/bin/git /extracted/bin/ && \
    # Copy the core C runtime layer (musl)
    cp /lib/ld-musl-*.so.1 /extracted/lib/ && \
    # FIX: Copy libz from /usr/lib/ instead of /lib/
    cp /usr/lib/libz.so.1 /extracted/usr/lib/ && \
    cp /usr/lib/libpcre2-8.so.0 /extracted/usr/lib/ && \
    # NETWORKING FIXES: Copy SSL/Crypto dependencies for secure HTTPS remote git connections
    cp /lib/libcrypto.so.3 /extracted/lib/ && \
    cp /lib/libssl.so.3 /extracted/lib/ && \
    # SYSTEM FIXES: Copy core protocol files so Git can resolve domain names/ports
    cp /etc/passwd /extracted/etc/passwd && \
    cp /etc/protocols /extracted/etc/protocols && \
    # Copy Git's core internal scripts/executables
    cp -r /usr/libexec/git-core /extracted/usr/libexec/


# ==============================================================================
# STAGE 2: The Final True "FROM scratch" Container
# ==============================================================================
FROM scratch

# Bring over only the static binaries and the Zig library
COPY --from=builder /extracted/ /

# Provide basic PATH settings so running 'zig' works out of the box
ENV PATH=/bin:/usr/bin
ENV ZIG_GLOBAL_CACHE_DIR=/tmp
# Drop straight into your custom standalone shell prompt!
CMD ["/bin/sh"]
