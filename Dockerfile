FROM debian:bookworm-slim

# SSL-VPN 클라이언트 + SSH/SFTP/전송 도구
RUN apt-get update && apt-get install -y --no-install-recommends \
        openvpn \
        curl \
        jq \
        openssh-client \
        sshpass \
        rsync \
        unzip \
        zip \
        iproute2 \
        iputils-ping \
        netcat-openbsd \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
COPY scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh
ENV PATH="/opt/scripts:${PATH}"

# VPN을 띄운 뒤 컨테이너를 유지. 이후 exec로 ssh/scp 사용.
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
