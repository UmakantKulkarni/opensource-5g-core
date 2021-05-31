FROM golang:1.16

RUN apt -y update
RUN apt -y install wget git iputils-ping tcpdump net-tools nano make iproute2 vim g++ libsctp-dev lksctp-tools libssl-dev

RUN cd ~ && wget https://github.com/Kitware/CMake/releases/download/v3.20.3/cmake-3.20.3.tar.gz && tar -xvzf cmake-3.20.3.tar.gz
RUN cd ~/cmake-3.20.3 && ./bootstrap -- -DCMAKE_BUILD_TYPE:STRING=Release && make && make install
RUN cmake --version
RUN rm -rf ~/cmake-3.20.3*

RUN git clone https://github.com/aligungr/UERANSIM && cd UERANSIM && make
COPY ./*.yaml /UERANSIM/config/

WORKDIR $GOPATH/src
RUN git clone --recursive -j `nproc` https://github.com/free5gc/free5gc.git

WORKDIR $GOPATH/src/free5gc
RUN git checkout main
RUN git submodule sync
RUN git submodule update --init --jobs `nproc`
RUN git submodule foreach git checkout main
RUN git submodule foreach git pull --jobs `nproc`

WORKDIR $GOPATH/src/free5gc/test
RUN go mod download github.com/free5gc/pfcp
COPY mytests $GOPATH/src/free5gc/test/mytests
COPY ./*.go ./

WORKDIR $GOPATH/src/free5gc/test/mytests
RUN go build reg.go
RUN go build delSesDbData.go
RUN go build app.go

ENV GIN_MODE=release

CMD ["sh", "-c", "sleep infinity"]
