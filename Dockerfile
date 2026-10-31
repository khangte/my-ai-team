# install/docker.sh가 사용하는 팀 환경 이미지.
# /home/user는 볼륨에 가려지므로 도구는 /opt 아래에 설치한다.

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
    python3 \
    && locale-gen ko_KR.UTF-8 \
    && update-locale LANG=ko_KR.UTF-8 \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ko_KR.UTF-8
ENV LANGUAGE=ko_KR:ko
ENV LC_ALL=ko_KR.UTF-8

ENV NPM_CONFIG_PREFIX=/opt/npm-global
ENV PATH=/opt/npm-global/bin:$PATH

ENV RTK_INSTALL_DIR=/opt/rtk-bin
ENV PATH=/opt/rtk-bin:$PATH

RUN useradd -m -s /bin/bash user

RUN mkdir -p /opt/npm-global /opt/rtk-bin /opt/ai-setup /workspace && \
    chown -R user:user /opt/npm-global /opt/rtk-bin /opt/ai-setup /workspace

USER user
WORKDIR /workspace

RUN npm install -g @anthropic-ai/claude-code @openai/codex

# 빌드 재현성을 위해 버전을 고정한다.
ENV RTK_VERSION=v0.43.0
RUN curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh

# 자주 바뀌는 저장소 파일은 마지막에 복사해 위 CLI 설치 레이어 캐시를 유지한다.
COPY --chown=user:user setup-team.sh /opt/ai-setup/setup-team.sh
COPY --chown=user:user team /opt/ai-setup/team
COPY --chown=user:user bin /opt/ai-setup/bin
COPY --chown=user:user CLAUDE.md AGENTS.md /opt/ai-setup/

CMD ["bash"]
