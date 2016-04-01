FROM alpine:3.3

ENV PACKAGES "git openssh-client gnupg jq"

RUN apk add --update $PACKAGES && rm -rf /var/cache/apk/*

COPY assets/ /opt/resource/
RUN chmod +x /opt/resource/*

COPY scripts/install_git_lfs.sh install_git_lfs.sh
RUN ./install_git_lfs.sh

RUN git config --global user.email "concourse@foo.bar" && \
    git config --global user.name "Docker container"

COPY test/ /opt/resource-tests/
RUN /opt/resource-tests/all.sh && \
  rm -rf /tmp/*
