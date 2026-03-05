FROM alpine:3.23

RUN apk update
RUN apk add alpine-sdk doas doas-sudo-shim vim wget
RUN adduser -D -u 1000 ciuser
RUN adduser ciuser abuild
RUN echo 'permit nopass root' >> /etc/doas.conf
RUN echo 'permit nopass :abuild' >> /etc/doas.conf
RUN echo 'permit nopass ciuser' >> /etc/doas.conf

CMD ["/bin/ash"]
