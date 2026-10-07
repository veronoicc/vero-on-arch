FROM archlinux:base-devel

# Enable parallel downloads and setup keyring/mirrors
RUN sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Syu --noconfirm \
        git \
        sudo \
        curl \
        wget \
        jq \
        tar \
        xz \
        zstd \
        bc \
        cpio \
        gettext \
        libelf \
        pahole \
        perl \
        python \
        rust \
        rust-src \
        rust-bindgen \
        clang \
        llvm \
        lld \
        ccache \
        icu \
        krb5 \
        openssl \
        zlib \
        libunwind \
        lttng-ust \
        devtools \
        namcap \
        nvchecker \
        github-cli \
        pacman-contrib \
        pnpm \
        bun \
        nodejs \
        npm && \
    pacman -Scc --noconfirm

# Enable ccache in makepkg and optimize compression
RUN sed -i 's/!ccache/ccache/' /etc/makepkg.conf && \
    sed -i 's/^#*COMPRESSZST=.*/COMPRESSZST=(zstd -c -z -q -T0 -1)/' /etc/makepkg.conf

# Create non-root builder user with passwordless sudo
RUN useradd -m -s /bin/bash -u 1000 builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 0440 /etc/sudoers.d/builder

# Setup default ccache configuration for builder user
RUN mkdir -p /home/builder/.config/ccache /home/builder/.cache && \
    printf 'max_size = 50G\nsloppiness = time_macros,include_file_mtime,file_macro\nhash_dir = false\n' > /home/builder/.config/ccache/ccache.conf && \
    chown -R builder:builder /home/builder/.config /home/builder/.cache

# Build and install yay-bin as builder user
USER builder
WORKDIR /tmp
RUN git clone https://aur.archlinux.org/yay-bin.git && \
    cd yay-bin && \
    makepkg -si --noconfirm && \
    cd /tmp && \
    rm -rf yay-bin

USER root
# Provide paru alias for compatibility
RUN ln -sf /usr/bin/yay /usr/local/bin/paru

# Install GitHub Actions Runner
ARG RUNNER_VERSION=2.337.0
WORKDIR /home/builder/actions-runner
RUN curl -o actions-runner-linux-x64.tar.gz -L \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" && \
    tar xzf actions-runner-linux-x64.tar.gz && \
    rm -f actions-runner-linux-x64.tar.gz && \
    chown -R builder:builder /home/builder

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER builder
WORKDIR /home/builder/actions-runner

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/home/builder/actions-runner/run.sh"]
