FROM --platform=linux/amd64 ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv python3-pip build-essential patchelf libgl1 libegl1 libglib2.0-0 libxkbcommon-x11-0 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-shape0 libxcb-xinerama0 libxcb-randr0 libxcb-xfixes0 libxcb-sync1 libxcb-util1 libxcb-xkb1 libdbus-1-3 libfontconfig1 libpulse0 xvfb xauth openbox xdotool dbus-x11 curl ca-certificates && rm -rf /var/lib/apt/lists/*
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:$PATH"
WORKDIR /workspace
