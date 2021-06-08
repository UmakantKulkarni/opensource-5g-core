FROM ubuntu:18.04

RUN apt -y update

RUN apt -y install wget git vim nano make g++ libsctp-dev lksctp-tools net-tools iproute2 libssl-dev tcpdump curl jq iputils-ping

RUN cd && wget https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3.tar.gz && tar -xvzf cmake-3.20.3.tar.gz

RUN cd && cd cmake-3.20.3 && ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release && make && make install

RUN cd && rm -rf cmake-*

RUN cmake --version

RUN cd && git clone -b v3.2.0 https://github.com/aligungr/UERANSIM && cd UERANSIM && make

WORKDIR /root/

COPY ./*.yaml UERANSIM/config/

COPY ./*.sh UERANSIM/

RUN cp UERANSIM/build/nr-* /usr/local/bin/

CMD ["sh", "-c", "sleep infinity"]
