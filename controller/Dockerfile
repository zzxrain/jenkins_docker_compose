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

RUN mkdir -p /usr/share/jenkins/ref/plugins \
 && jenkins-plugin-cli \
      --plugin-file /usr/share/jenkins/ref/plugins.txt \
      --plugin-download-directory /usr/share/jenkins/ref/plugins \
      --verbose \
 && test -s /usr/share/jenkins/ref/plugins/configuration-as-code.jpi \
 && test -s /usr/share/jenkins/ref/plugins/matrix-auth.jpi \
 && test -s /usr/share/jenkins/ref/plugins/ssh-slaves.jpi