FROM erlang:22-alpine as builder

RUN apk update && apk add make g++ git coreutils cmake

WORKDIR /arweave

ADD Makefile Emakefile rebar3 rebar.config rebar.lock docker-arweave-server ./
ADD _checkouts _checkouts
ADD data data
ADD bin bin
ADD lib lib
ADD src src
ADD c_src c_src

# E.g. "-DTARGET_TIME=5 -DRETARGET_BLOCKS=10" or "-DFIXED_DIFF=2"
ARG ERLC_OPTS

RUN mkdir ebin
RUN make compile_prod
RUN make build_arweave

EXPOSE 1984
ENTRYPOINT ["./docker-arweave-server"]
