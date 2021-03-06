#------------------------------------------------------------------------------------
#--------------------------build-----------------------------------------------------
#------------------------------------------------------------------------------------
FROM ubuntu:xenial as build

RUN apt-get update && \
    apt-get install -y aptitude gcc g++ make patch unzip python build-essential \
    autoconf automake libtool pkg-config libxml2-dev zlib1g-dev openssl libssl-dev\
    liblzma-dev libzip-dev libbz2-dev git cmake extra-cmake-modules libcurl4-openssl-dev

# Libs path for ffmpeg(depends on serval libs).
ENV PKG_CONFIG_PATH /usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig


# Build srt
RUN cd /tmp && git clone https://github.com/Haivision/srt.git && cd srt \ 
&& cmake . -DENABLE_LOGGING=1 -DENABLE_PROFILE=1 -DENABLE_STATIC=1  -DUSE_STATIC_LIBSTDCXX=1 -DENABLE_THREAD_CHECK=0 \
&& make && make install

# Build Tsduck
RUN cd /tmp && git clone https://github.com/tsduck/tsduck.git && cd tsduck && ./build/install-prerequisites.sh \
&&  make NOPCSC=1 NOCURL=1 NODTAPI=1 NOSRT=0 NOTEST=1 \
&&  make install 

# For FFMPEG
ADD nasm-2.14.tar.bz2 /tmp
ADD yasm-1.2.0.tar.bz2 /tmp
ADD fdk-aac-0.1.3.tar.bz2 /tmp
ADD lame-3.99.5.tar.bz2 /tmp
ADD speex-1.2rc1.tar.bz2 /tmp
ADD x264-snapshot-20181116-2245.tar.bz2 /tmp
ADD ffmpeg-4.2.1.tar.bz2 /tmp
RUN cd /tmp/nasm-2.14 && ./configure && make && make install && \
    cd /tmp/yasm-1.2.0 && ./configure && make && make install && \
    cd /tmp/fdk-aac-0.1.3 && bash autogen.sh && ./configure && make && make install && \
    cd /tmp/lame-3.99.5 && ./configure && make && make install && \
    cd /tmp/speex-1.2rc1 && ./configure && make && make install && \
    cd /tmp/x264-snapshot-20181116-2245 && ./configure --disable-cli --enable-static && make && make install

RUN cd /tmp/ffmpeg-4.2.1 && ./configure --enable-pthreads --extra-libs=-lpthread \
        --enable-gpl --enable-nonfree \
        --enable-postproc --enable-bzlib --enable-zlib \
        --enable-libx264 --enable-libmp3lame --enable-libfdk-aac --enable-libspeex \
        --enable-libxml2 --enable-demuxer=dash --enable-libsrt  \
        --pkg-config-flags='--static' && \
    (cd /usr/local/lib && mkdir -p tmp && mv *.so* *.la tmp && echo "Force use static libraries") && \
	make && make install && echo "FFMPEG build and install successfully" && \
    (cd /usr/local/lib && mv tmp/* . && rmdir tmp)

#------------------------------------------------------------------------------------
#--------------------------dist------------------------------------------------------
#------------------------------------------------------------------------------------
FROM ubuntu:xenial as dist

WORKDIR /tmp/srs

RUN mkdir -p /usr/lib64
COPY --from=build /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
#Original one doesn't fly
#COPY --from=build /usr/local/lib/libssl.a /usr/local/lib64/libssl.a
COPY --from=build /lib/x86_64-linux-gnu/libssl.so.1.0.0 /usr/local/lib64/libssl.so.1.0.0
COPY --from=build /lib/x86_64-linux-gnu/libssl.so.1.0.0 /usr/local/lib64/libssl.so
COPY --from=build /usr/lib/x86_64-linux-gnu/libssl.a /usr/local/lib64/libssl.a
COPY --from=build /lib/x86_64-linux-gnu/libcrypto.so.1.0.0 /usr/local/lib64/libcrypto.so
COPY --from=build  /usr/lib/x86_64-linux-gnu/libcrypto.a /usr/local/lib64/libcrypto.a
#COPY --from=build /usr/local/lib/libcrypto.a /usr/local/lib64/libcrypto.a
COPY --from=build /usr/include/openssl /usr/local/include/openssl

# copy binary srt

COPY --from=build /usr/local/bin/srt-ffplay /usr/local/bin/srt-ffplay
COPY --from=build /usr/local/bin/srt-live-transmit /usr/local/bin/srt-live-transmit
COPY --from=build /usr/local/bin/srt-file-transmit /usr/local/bin/ssrt-file-transmit
COPY --from=build /usr/local/bin/srt-tunnel /usr/local/bin/srt-tunnel

# Copy libsrt 
COPY --from=build /usr/local/lib/libsrt.a /usr/lib64/libsrt.a
COPY --from=build /usr/local/lib/libsrt.so.1.4.1 /usr/lib64/libsrt.so.1.4.1
COPY --from=build /usr/local/lib/libsrt.so.1 /usr/lib64/libsrt.so.1
COPY --from=build /usr/local/lib/libsrt.so /usr/lib64/libsrt.so
COPY --from=build /usr/local/include/srt /usr/local/include/srt
COPY --from=build /usr/local/lib/pkgconfig /usr/local/lib/pkgconfig/

#Copy tsduck
ADD bin /usr/bin
ADD etc/udev/rules.d/80-tsduck.rules /etc/udev/rules.d/80-tsduck.rules
ADD etc/security/console.perms.d/80-tsduck.perms  /etc/security/console.perms.d/80-tsduck.perms
RUN ["chmod", "755", "/etc/udev/rules.d"]
RUN ["chmod", "644", "/etc/udev/rules.d/80-tsduck.rules"]
RUN ["chmod", "755", "/etc/security/console.perms.d"]
RUN ["chmod", "644", "/etc/security/console.perms.d/80-tsduck.perms"]


# Note that git is very important for codecov to discover the .codecov.yml
RUN apt-get update && \
    apt-get install -y aptitude gcc g++ make patch unzip python git libssl-dev \
        autoconf automake libtool pkg-config libxml2-dev liblzma-dev curl net-tools

# Install cherrypy for HTTP hooks.
ADD CherryPy-3.2.4.tar.gz2 /tmp
RUN cd /tmp/CherryPy-3.2.4 && python setup.py install

ENV PATH $PATH:/usr/local/go/bin
RUN cd /usr/local && \
    curl -L -O https://dl.google.com/go/go1.13.5.linux-amd64.tar.gz && \
    tar xf go1.13.5.linux-amd64.tar.gz && \
    rm -f go1.13.5.linux-amd64.tar.gz

# Now go with full srs
RUN cd /tmp && git clone https://github.com/ossrs/srs.git \
&& cd /tmp/srs && git checkout 4.0release \
&& cd /tmp/srs/trunk && ./configure \
&& make &&  make install
