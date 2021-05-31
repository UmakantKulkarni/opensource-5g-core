FROM ubuntu:18.04

RUN apt -y update

RUN apt -y install wget git vim nano make g++ libsctp-dev lksctp-tools net-tools iproute2 libssl-dev

RUN cd ~ && wget https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3.tar.gz && tar -xvzf cmake-3.20.3.tar.gz

RUN cd ~/cmake-3.20.3 && ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release && make && make install

RUN cmake --version

RUN rm -rf ~/cmake-3.20.3*

RUN git clone https://github.com/aligungr/UERANSIM && cd UERANSIM && make

COPY ./*.yaml /UERANSIM/config/

CMD ["sh", "-c", "sleep infinity"]
