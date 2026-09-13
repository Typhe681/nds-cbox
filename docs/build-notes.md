# Working build recipe for nds-shell on DSi (BlocksDS + MbedTLS)

## Setup

  wf-pacman -Sy
  wf-pacman -S blocksds-toolchain

  Add to ~/.bashrc:
    export PATH=/opt/wonderful/bin:$PATH
    export WONDERFUL_TOOLCHAIN=/opt/wonderful
    export BLOCKSDS=/opt/wonderful/thirdparty/blocksds/core

  If `wf-pacman -Ss blocksds` returns nothing, the repo config isn't
  being loaded. pacman.conf only includes /etc/pacman.d/*.conf, so
  wonderful's own config dir gets ignored:
    sudo cp /opt/wonderful/pacman/config/10-blocksds.conf /opt/wonderful/etc/pacman.d/

## Configure this dih

  cd ~/Desktop/nds-cbox
  rm -rf build
  cmake --preset blocksds-release \
    -DCMAKE_C_FLAGS="-Wno-stringop-truncation -DSSIZE_MAX=2147483647" \
    -DNDSH_SSL_BACKEND=MbedTLS

## Patch curl (REQUIRED AFTER EVERY CLEAN CONFIGURE)

  cd build/_deps/curl-src
  sed -i 's/fcntl(\*sockfd, F_SETFD, FD_CLOEXEC)/0/' lib/cf-socket.c
  sed -i 's/fcntl(s_accepted, F_SETFD, FD_CLOEXEC)/0/' lib/cf-socket.c


## Can we build it? YES WE CAN

  cd ~/Desktop/nds-cbox
  cmake --build build -j$(nproc)

## Why the flags?

  -DNDSH_SSL_BACKEND=MbedTLS
    Case-sensitive. Use MbedTLS because WolfSSL on ARM32 needs a ton of SP-math config for RSA-4096 and this is just easier

  -DSSIZE_MAX=2147483647
    Picolibc defines SSIZE_MAX as a cast expression, which the preprocessor can't evaluate. Curl's warnless.c does `#if INT_MAX < SSIZE_MAX` and fails without this.

  -Wno-stringop-truncation
    GCC 16 flags a strncpy in WolfSSL as an error. Harmless to keep :shrug:

  curl patch
    DS socket layer doesn't have FD_CLOEXEC, so curl explodes on the failed fcntl. Wiped by rm -rf build. Reapply after every reconfigure :P


## CA bundle

  Curl needs a CA bundle at the SD root called tls-ca-bundle.pem or
  every HTTPS call fails with "error setting certificate verify
  locations".

    On PC:
    curl https://curl.se/ca/cacert.pem >tls-ca-bundle.pem
    python3 -m http.server 8000

    On DSi:
    curl http://<ipherepls>:8000/tls-ca-bundle.pem >tls-ca-bundle.pem

  No space after the >, idk why
  Could also just move the file manually instead of http but whatever


## Moving rom

  just curl/transfer ts under a new name and reboot (twilight menu my beloved <3)
