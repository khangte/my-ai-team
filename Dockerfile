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
    && npm install -g @anthropic-ai/claude-code \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ko_KR.UTF-8
ENV LANGUAGE=ko_KR:ko
ENV LC_ALL=ko_KR.UTF-8

# 일반 사용자 생성
RUN useradd -m -s /bin/bash user

# 작업 디렉터리 생성 및 권한 부여
RUN mkdir -p /workspace && \
    chown -R user:user /workspace

WORKDIR /workspace

USER user

CMD ["bash"]
