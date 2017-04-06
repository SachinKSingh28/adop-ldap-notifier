FROM alpine:3.3

RUN apk add --update --no-cache bash mailx openldap-clients gawk curl

COPY tasks/ /etc/periodic/
RUN chmod -R +x /etc/periodic/

CMD ["crond", "-f", "-d", "8"]

