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

# Copy as root, but explicitly assign ownership and readable permissions.
COPY --chown=jenkins:jenkins plugins.txt /usr/share/jenkins/ref/plugins.txt

RUN chmod 0644 /usr/share/jenkins/ref/plugins.txt \
 && mkdir -p /usr/share/jenkins/ref/plugins \
 && chown -R jenkins:jenkins /usr/share/jenkins/ref

USER jenkins

# Fail early if plugins.txt is missing, unreadable, empty, or malformed.
RUN echo "==== plugins.txt metadata ====" \
 && ls -lah /usr/share/jenkins/ref/plugins.txt \
 && echo "==== plugins.txt content ====" \
 && cat /usr/share/jenkins/ref/plugins.txt \
 && echo "==== install plugins ====" \
 && jenkins-plugin-cli \
      --plugin-file /usr/share/jenkins/ref/plugins.txt \
      --plugin-download-directory /usr/share/jenkins/ref/plugins \
      --verbose \
 && echo "==== installed plugins ====" \
 && find /usr/share/jenkins/ref/plugins -maxdepth 1 -type f | sort \
 && test -s /usr/share/jenkins/ref/plugins/configuration-as-code.jpi \
 && test -s /usr/share/jenkins/ref/plugins/matrix-auth.jpi \
 && test -s /usr/share/jenkins/ref/plugins/ssh-slaves.jpi