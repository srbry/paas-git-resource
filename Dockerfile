FROM alpine:3.3

ENV LANG C
ENV PACKAGES "git openssh-client gnupg jq perl"

RUN apk add --update $PACKAGES && rm -rf /var/cache/apk/*

#ADD http://stedolan.github.io/jq/download/linux64/jq /usr/local/bin/jq
#RUN chmod +x /usr/local/bin/jq

ADD assets/ /opt/resource/
RUN chmod +x /opt/resource/*

ADD scripts/install_git_lfs.sh install_git_lfs.sh
RUN ./install_git_lfs.sh

RUN git config --global user.email "concourse@foo.bar" && \
    git config --global user.name "Docker container"

ADD test/ /opt/resource-tests/
RUN /opt/resource-tests/all.sh && \
  rm -rf /tmp/*
