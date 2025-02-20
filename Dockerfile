ARG DISTRO=noble
ARG CLANG_MAJOR=18
# clang source options:
# apt - directly use apt version
# llvm - add llvm distro repo
ARG CLANG_SOURCE=llvm
ARG GCC_MAJOR=14
# gcc source options:
# apt - directly use apt version
# ppa - add toolchain ppa
ARG GCC_SOURCE=apt
ARG QT_ARCH=gcc_64
ARG QT_VERSION=6.7.1
ARG QT_MODULES=""
ARG CLANG_QT_URL=https://github.com/arBmind/qt5/releases/download/v6.5.3/qt653_clang17.tgz
ARG QT_EXTRAS_URL=https://github.com/arBmind/qt5/releases/download/v6.5.3/extra_libs.tgz
ARG CMAKE_VERSION=3.29.5
ARG CMAKE_URL=https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz
# Ubuntu lunar
#ARG RUNTIME_APT="libicu72 libgssapi-krb5-2 libdbus-1-3 libpcre2-16-0"
# Ubuntu noble
ARG RUNTIME_APT="libicu74 libgssapi-krb5-2 libdbus-1-3 libpcre2-16-0"
# use "cmake-gcc-qt" or "cmake-clang-libstdcpp-qt"
ARG QTGUI_BASE_IMAGE="cmake-gcc-qt"
# note: these depend on distro and Qt version
ARG QTGUI_PACKAGES=libegl-dev \
  libglu1-mesa-dev \
  libgl-dev \
  libopengl-dev \
  libxkbcommon-dev \
  libfontconfig1-dev \
  xdg-utils \
  libxcb-keysyms1 \
  libxcb-render-util0 \
  libxcb-xfixes0 \
  libxcb-icccm4 \
  libxcb-image0 \
  libxcb-shape0 \
  libgssapi-krb5-2 \
  libxcb-xinerama0 \
  libxcb-xkb1 \
  libxkbcommon-x11-0 \
  libxcb-randr0

# base Qt setup
FROM python:3.10-slim as qt_base
ARG QT_ARCH
ARG QT_VERSION
ARG QT_MODULES
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ARG DEBIAN_FRONTEND=noninteractive

RUN pip install aqtinstall

RUN \
  apt update --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
    p7zip-full \
    libglib2.0-0 \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

RUN \
  mkdir /qt && cd /qt \
  && aqt install-qt linux desktop ${QT_VERSION} ${QT_ARCH} -m ${QT_MODULES} --external $(which 7zr)


# base CMake setup
FROM ubuntu:${DISTRO} AS cmake_base
ARG CMAKE_URL
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ARG DEBIAN_FRONTEND=noninteractive

RUN \
  apt-get update --quiet \
  && apt-get upgrade --yes --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
    ca-certificates \
    wget \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*

RUN \
  mkdir -p /opt/cmake \
  && wget -q -c ${CMAKE_URL} -O - | tar --strip-components=1 -xz -C /opt/cmake


# base compiler setup for GCC
FROM ubuntu:${DISTRO} AS gcc_base
ARG DISTRO
ARG GCC_MAJOR
ARG GCC_SOURCE
ARG RUNTIME_APT
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ARG DEBIAN_FRONTEND=noninteractive

ENV \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8

# install GCC
RUN \
  apt-get update --quiet \
  && apt-get upgrade --yes --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
    libglib2.0-0 \
    apt-transport-https \
    ca-certificates \
    gnupg \
    wget \
  && if [ "$GCC_SOURCE" = "ppa" ] ; then \
    wget -qO - "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x60c317803a41ba51845e371a1e9377a2ba9ef27f" | apt-key add - \
    && echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu ${DISTRO} main" > /etc/apt/sources.list.d/gcc.list \
    && apt-get update --quiet \
    ; fi \
  && apt-get install --yes --quiet --no-install-recommends \
    git \
    ninja-build \
    make \
    libstdc++-${GCC_MAJOR}-dev \
    gcc-${GCC_MAJOR} \
    g++-${GCC_MAJOR} \
    ${RUNTIME_APT} \
  && update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-${GCC_MAJOR} 100 \
  && update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-${GCC_MAJOR} 100 \
  && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${GCC_MAJOR} 100 \
  && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_MAJOR} 100 \
  && c++ --version \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*


# final cmake-gcc (no Qt)
FROM gcc_base AS cmake-gcc
ARG DISTRO
ARG GCC_MAJOR
ARG CMAKE_VERSION

LABEL Description="Ubuntu ${DISTRO} - Gcc${GCC_MAJOR} + CMake ${CMAKE_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
ENV \
  PATH=/opt/cmake/bin:${PATH}


# final cmake-gcc-gt (with Qt)
FROM gcc_base AS cmake-gcc-qt
ARG DISTRO
ARG GCC_MAJOR
ARG CMAKE_VERSION
ARG QT_VERSION
ARG QT_ARCH

LABEL Description="Ubuntu ${DISTRO} - Gcc${GCC_MAJOR} + CMake ${CMAKE_VERSION} + Qt ${QT_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
COPY --from=qt_base /qt/${QT_VERSION} /qt/${QT_VERSION}
ENV \
  QTDIR=/qt/${QT_VERSION}/gcc_64 \
  PATH=/qt/${QT_VERSION}/gcc_64/bin:/opt/cmake/bin:${PATH} \
  LD_LIBRARY_PATH=/qt/${QT_VERSION}/gcc_64/lib:${LD_LIBRARY_PATH}


# base compiler setup for Clang
FROM ubuntu:${DISTRO} AS clang_base
ARG DISTRO
ARG CLANG_MAJOR
ARG CLANG_SOURCE
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ARG DEBIAN_FRONTEND=noninteractive
ARG RUNTIME_APT

ENV \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8

# install Clang (https://apt.llvm.org/)
RUN apt-get update --quiet \
  && apt-get upgrade --yes --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
    libglib2.0-0 \
    wget \
    gnupg \
    apt-transport-https \
    ca-certificates \
  && if [ "$CLANG_SOURCE" = "llvm" ] ; then \
    wget -qO - https://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add - \
    && echo "deb http://apt.llvm.org/${DISTRO}/ llvm-toolchain-${DISTRO}-${CLANG_MAJOR} main" > /etc/apt/sources.list.d/llvm.list \
    && apt-get update --quiet \
    ; fi \
  && apt-get install --yes --quiet --no-install-recommends \
    git \
    ninja-build \
    make \
    ${RUNTIME_APT} \
    clang-${CLANG_MAJOR} \
    lld-${CLANG_MAJOR} \
    libc++abi-${CLANG_MAJOR}-dev \
    libc++-${CLANG_MAJOR}-dev \
    $( [ $CLANG_MAJOR -ge 12 ] && echo "libunwind-${CLANG_MAJOR}-dev" ) \
  && update-alternatives --install /usr/bin/cc cc /usr/bin/clang-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_MAJOR} 100 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.lld-${CLANG_MAJOR} 10 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.gold 20 \
  && update-alternatives --install /usr/bin/ld ld /usr/bin/ld.bfd 30 \
  && c++ --version \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*


# final cmake-clang (no Qt)
FROM clang_base AS cmake-clang
ARG DISTRO
ARG CLANG_MAJOR
ARG CMAKE_VERSION

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + CMake ${CMAKE_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
ENV \
  PATH=/opt/cmake/bin:${PATH}


# final cmake-clang-qt (with Qt)
FROM clang_base AS cmake-clang-qt
ARG DISTRO
ARG CLANG_MAJOR
ARG CMAKE_VERSION
ARG QT_VERSION
ARG CLANG_QT_URL
ARG QT_EXTRAS_URL

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + CMake ${CMAKE_VERSION} + Qt ${QT_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
RUN \
  mkdir -p /opt/qt${QT_VERSION} \
  && wget -q -c ${CLANG_QT_URL} -O - | tar --strip-components=1 -xz -C /opt/qt${QT_VERSION} \
  && wget -q -c ${QT_EXTRAS_URL} -O - | tar --strip-components=1 -xz -C /opt/qt${QT_VERSION}/lib

ENV \
  QTDIR=/opt/qt${QT_VERSION} \
  PATH=/opt/qt${QT_VERSION}/bin:/opt/cmake/bin:${PATH} \
  LD_LIBRARY_PATH=/opt/qt${QT_VERSION}/lib:${LD_LIBRARY_PATH}



FROM clang_base AS clang_libstdcpp_base
ARG DISTRO
ARG GCC_MAJOR
ARG GCC_SOURCE
ARG APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ARG DEBIAN_FRONTEND=noninteractive

RUN \
  if [ "$GCC_SOURCE" = "ppa" ] ; then \
    wget -qO - "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x60c317803a41ba51845e371a1e9377a2ba9ef27f" | apt-key add - \
    && echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu ${DISTRO} main" > /etc/apt/sources.list.d/gcc.list \
    && apt-get update --quiet \
    ; fi \
  && apt-get install --yes --quiet --no-install-recommends \
    libstdc++-${GCC_MAJOR}-dev \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*


# final cmake-clang-libstdcpp (no Qt)
FROM clang_libstdcpp_base AS cmake-clang-libstdcpp
ARG DISTRO
ARG CLANG_MAJOR
ARG GCC_MAJOR
ARG CMAKE_VERSION

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + Libstdc++-${GCC_MAJOR} + CMake ${CMAKE_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
ENV \
  PATH=/opt/cmake/bin:${PATH}


# final cmake-clang-qt (with Qt)
FROM clang_libstdcpp_base AS cmake-clang-libstdcpp-qt
ARG DISTRO
ARG CLANG_MAJOR
ARG GCC_MAJOR
ARG CMAKE_VERSION
ARG QT_VERSION
ARG QT_ARCH

LABEL Description="Ubuntu ${DISTRO} - Clang${CLANG_MAJOR} + Libstdc++-${GCC_MAJOR} + CMake ${CMAKE_VERSION} + Qt ${QT_VERSION}"
LABEL org.opencontainers.image.source = "https://github.com/arBmind/cmake-containers"

COPY --from=cmake_base /opt/cmake /opt/cmake
COPY --from=qt_base /qt/${QT_VERSION} /qt/${QT_VERSION}
ENV \
  QTDIR=/qt/${QT_VERSION}/gcc_64 \
  PATH=/qt/${QT_VERSION}/gcc_64/bin:/opt/cmake/bin:${PATH} \
  LD_LIBRARY_PATH=/qt/${QT_VERSION}/gcc_64/lib:${LD_LIBRARY_PATH}


# final qtqui (as developer setup)
FROM ${QTGUI_BASE_IMAGE} AS cmake-qtgui-dev
ARG QTGUI_PACKAGES

RUN \
  apt update --quiet \
  && apt-get install --yes --quiet --no-install-recommends \
    ${QTGUI_PACKAGES} \
    gdb \
  && apt-get --yes autoremove \
  && apt-get clean autoclean \
  && rm -rf /var/lib/apt/lists/{apt,dpkg,cache,log} /tmp/* /var/tmp/*
