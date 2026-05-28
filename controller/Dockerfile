FROM jenkins/jenkins:2.555.2-lts-jdk21

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl \
      git \
      ca-certificates \
      zip \
      unzip \
      jq \
 && rm -rf /var/lib/apt/lists/*

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli -f /usr/share/jenkins/ref/plugins.txt