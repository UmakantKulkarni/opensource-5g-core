FROM ubuntu:20.04

ENV DEBIAN_FRONTEND noninteractive

RUN apt -y update

RUN apt -y install wget git vim nano make g++ libsctp-dev lksctp-tools net-tools iproute2 libssl-dev tcpdump curl jq iputils-ping gdb

RUN cd && wget https://github.com/Kitware/CMake/releases/download/v3.21.0/cmake-3.21.0.tar.gz && tar -xvzf cmake-3.21.0.tar.gz

RUN cd && cd cmake-3.21.0 && ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release && make && make install

RUN cd && rm -rf cmake-*

RUN cmake --version

ENV PCS_SETUP_TUN_INTF=false

RUN cd && git clone -b 375d538_v3.2.2 https://github.com/UmakantKulkarni/UERANSIM && cd UERANSIM && make

WORKDIR /root/

RUN git clone https://github.com/UmakantKulkarni/scripts && cd scripts && chmod +x *

RUN cp UERANSIM/build/nr-* /usr/local/bin/

CMD ["sh", "-c", "sleep infinity"]
