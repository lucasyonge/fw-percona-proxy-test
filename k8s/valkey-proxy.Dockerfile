FROM debian:12 as build

RUN apt update
RUN apt install -y openssl git make clang build-essential libssl-dev

WORKDIR /opt
RUN git clone https://github.com/valkey-io/valkey-proxy
WORKDIR /opt/valkey-proxy
RUN make

FROM debian:12
RUN apt update 
RUN apt install -y openssl
COPY --from=build /opt/valkey-proxy/valkey-proxy /usr/local/bin/valkey-proxy
CMD [ "valkey-proxy" ]
