FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV ORPHEUS_MODEL_NAME=Orpheus-3b-FT-Q4_K_M.gguf
ENV ORPHEUS_MAX_TOKENS=8192
ENV ORPHEUS_API_URL=http://127.0.0.1:8080
ENV ORPHEUS_PORT=5005
ENV PATH="/app/venv/bin:$PATH"

# --- 1. Instalar dependencias del sistema ---
RUN apt-get update && apt-get install -y \
    git curl wget build-essential cmake \
    libopenblas-dev python3.10 python3-pip python3-venv \
    libsndfile1 ffmpeg portaudio19-dev \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# --- 2. Clonar y compilar llama.cpp con CMake ---
WORKDIR /workspace
RUN git clone https://github.com/ggerganov/llama.cpp.git && \
    cd llama.cpp && mkdir build && cd build && \
    cmake .. -DLLAMA_CUBLAS=ON && \
    cmake --build . --target server -j $(nproc)

# --- 3. Descargar modelo GGUF ---
RUN mkdir -p /workspace/models && \
    curl -L -o /workspace/models/orpheus.gguf \
    https://huggingface.co/lex-au/Orpheus-3b-FT-Q4_K_M/resolve/main/Orpheus-3b-FT-Q4_K_M.gguf

# --- 4. Crear usuario y entorno de trabajo ---
RUN useradd -m -u 1001 appuser && \
    mkdir -p /app/outputs /app && \
    chown -R appuser:appuser /app /workspace

USER appuser
WORKDIR /app

# --- 5. Copiar requirements e instalar entorno Python ---
COPY --chown=appuser:appuser requirements.txt .
RUN python3 -m venv /app/venv && \
    pip install --upgrade pip && \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124 && \
    pip install -r requirements.txt

# --- 6. Copiar el resto del código ---
COPY --chown=appuser:appuser . .

EXPOSE ${ORPHEUS_PORT}

# --- 7. Iniciar ambos servicios: llama.cpp + Orpheus-FASTAPI ---
CMD /bin/bash -c "\
  /workspace/llama.cpp/build/server \
    -m /workspace/models/orpheus.gguf \
    --ctx-size ${ORPHEUS_MAX_TOKENS} \
    --n-predict ${ORPHEUS_MAX_TOKENS} \
    --port 8080 \
    --rope-scaling linear & \
  uvicorn app:app --host 0.0.0.0 --port ${ORPHEUS_PORT}"
