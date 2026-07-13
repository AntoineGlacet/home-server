FROM python:3.11-slim

# Set noninteractive mode during package installation
ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /app

COPY ./requirements.txt /requirements.txt    
COPY ./logrotate.conf /etc/logrotate.d/minabot

# Install cron, logrotate, docker CLI and any needed packages specified in requirements.txt
RUN apt-get update && \
    apt-get install -y cron logrotate wget curl ca-certificates gnupg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli docker-compose-plugin procps && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache-dir -r /requirements.txt && \
    chmod 644 /etc/logrotate.d/minabot

WORKDIR /script

# make sure python prints to stdout
ENV PYTHONUNBUFFERED=1
