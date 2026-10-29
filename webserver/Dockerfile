FROM alpine:3.19

ENV TS_VERSION=3.13.7 \
    TS3SERVER_LICENSE=accept \
    TS3_ADMIN_PASSWORD=adminpass123

# libc6-compat, libstdc++, libgcc : shims requis pour le binaire glibc de TeamSpeak sur Alpine (musl)
RUN apk add --no-cache nginx bzip2 wget libc6-compat ca-certificates libstdc++ libgcc

# Utilisateur non-root pour le processus TS3 et répertoires Nginx
RUN adduser -D -h /opt/teamspeak teamspeak && \
    mkdir -p /run/nginx /var/log/nginx

WORKDIR /opt/teamspeak

RUN wget https://files.teamspeak-services.com/releases/server/${TS_VERSION}/teamspeak3-server_linux_amd64-${TS_VERSION}.tar.bz2 && \
    tar -xjvf teamspeak3-server_linux_amd64-${TS_VERSION}.tar.bz2 --strip-components=1 && \
    rm teamspeak3-server_linux_amd64-${TS_VERSION}.tar.bz2 && \
    touch .ts3server_license_accepted && \
    chown -R teamspeak:teamspeak /opt/teamspeak

RUN echo "0.0.0.0/0" > /opt/teamspeak/query_ip_allowlist.txt && \
    echo "::/0" >> /opt/teamspeak/query_ip_allowlist.txt

COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80 9987/udp 10011 30033

CMD ["/start.sh"]
