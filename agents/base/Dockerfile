FROM jenkins/ssh-agent:debian-jdk21

USER root

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      zip \
      unzip \
      jq \
      bash \
      procps \
      iputils-ping \
      netcat-openbsd \
 && rm -rf /var/lib/apt/lists/*

USER root