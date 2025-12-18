FROM alpine:3.20

RUN apk update \
 && apk add --no-cache alpine-sdk sudo

RUN adduser --disabled-password --uid 1000 dev \
 && addgroup dev abuild

RUN echo "dev ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

USER dev

ENTRYPOINT /bin/ash
