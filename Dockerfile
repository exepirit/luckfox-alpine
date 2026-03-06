FROM alpine:3.23

RUN apk update
RUN apk add alpine-sdk doas doas-sudo-shim vim wget
RUN adduser -D -u 1000 builder
RUN adduser builder abuild
RUN echo 'permit nopass root' >> /etc/doas.conf
RUN echo 'permit nopass :abuild' >> /etc/doas.conf
RUN echo 'permit nopass builder' >> /etc/doas.conf

CMD ["/bin/ash"]
