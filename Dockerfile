FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV ORPHEUS_MODEL_NAME=Orpheus-3b-FT-Q4_K_M.gguf
ENV ORPHEUS_MAX_TOKENS=8192
ENV ORPHEUS_API_URL=http://127.0.0.1:8080
ENV ORPHEUS_PORT=5005
ENV PATH="/app/venv/bin:$PATH"

# --- 1. System dependencies ---
RUN apt-get update && apt-get install -y \
    git build-essential wget curl \
    python3.10 python3-pip python3-venv \
    libsndfile1 ffmpeg portaudio19-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. llama.cpp build ---
WORKDIR /workspace
RUN git clone https://github.com/ggerganov/llama.cpp.git && \
    cd llama.cpp && make -j$(nproc) server

# --- 3. Download Orpheus model ---
RUN mkdir -p /workspace/models && \
    wget -O /workspace/models/orpheus.gguf \
    https://huggingface.co/lex-au/Orpheus-3b-FT-Q4_K_M/resolve/main/Orpheus-3b-FT-Q4_K_M.gguf

# --- 4. Install Orpheus-FASTAPI ---
WORKDIR /app
COPY requirements.txt .
RUN python3 -m venv /app/venv && \
    pip install --upgrade pip && \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    pip install -r requirements.txt

COPY . .

EXPOSE ${ORPHEUS_PORT}

# --- 5. Run both servers ---
CMD /bin/bash -c "\
    /workspace/llama.cpp/server \
        -m /workspace/models/orpheus.gguf \
        --ctx-size ${ORPHEUS_MAX_TOKENS} \
        --n-predict ${ORPHEUS_MAX_TOKENS} \
        --port 8080 \
        --rope-scaling linear & \
    uvicorn app:app --host 0.0.0.0 --port ${ORPHEUS_PORT}"
