FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    git \
    tmux \
    vim \
    locales \
    fonts-noto-cjk \
    && locale-gen ko_KR.UTF-8 \
    && update-locale LANG=ko_KR.UTF-8 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ko_KR.UTF-8
ENV LANGUAGE=ko_KR:ko
ENV LC_ALL=ko_KR.UTF-8

# npm 전역 설치 경로를 /home/user가 아닌 별도 경로로 지정
# (/home/user는 volume으로 덮어씌워지므로 여기 설치하면 안 됨)
ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV PATH=/opt/npm-global/bin:$PATH

# rtk도 동일한 이유로 volume 밖 경로에 설치
ENV RTK_INSTALL_DIR=/opt/rtk-bin
ENV PATH=/opt/rtk-bin:$PATH

# bun도 동일한 이유로 volume 밖 경로에 설치 (gstack 스킬 설치에 필요)
ENV BUN_INSTALL=/opt/bun
ENV PATH=/opt/bun/bin:$PATH

RUN useradd -m -s /bin/bash user

RUN mkdir -p /opt/npm-global /opt/rtk-bin /opt/bun /workspace && \
    chown -R user:user /opt/npm-global /opt/rtk-bin /opt/bun /workspace

USER user
WORKDIR /workspace

RUN npm install -g @anthropic-ai/claude-code

# 빌드 재현성을 위해 rtk 버전 고정 (업데이트 시 이 값만 올리면 됨)
ENV RTK_VERSION=v0.43.0
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

# gstack 스킬 설치(런타임, setup-team.sh)에 필요
RUN curl -fsSL https://bun.sh/install | bash

CMD ["bash"]
