#!/usr/bin/env python3
"""
Production-ready Modal app for private Qwen3.5-9B OpenAI-compatible serving via vLLM.

Usage:
  # 1) authenticate once (interactive)
  modal setup

  # 2) prefetch model weights into persistent volume (one-time)
  modal run scripts/modal_qwen35_9b_app.py::prefetch_model

  # 3) deploy endpoint
  modal deploy scripts/modal_qwen35_9b_app.py

This app is intended to be private via Modal proxy auth:
  - endpoint uses requires_proxy_auth=True
  - client must send Modal-Key / Modal-Secret headers
"""

import subprocess

import modal

APP_NAME = "private-modal-qwen35-9b"
MODEL_ID = "Qwen/Qwen3.5-9B-Instruct"
MODEL_VOLUME_NAME = "private-modal-qwen35-9b-model"
HF_CACHE_VOLUME_NAME = "private-modal-qwen35-9b-hf-cache"
VLLM_CACHE_VOLUME_NAME = "private-modal-qwen35-9b-vllm-cache"
VLLM_PORT = 8000

MODEL_MOUNT = "/models"
HF_CACHE_MOUNT = "/root/.cache/huggingface"
VLLM_CACHE_MOUNT = "/root/.cache/vllm"

app = modal.App(APP_NAME)

image = (
    modal.Image.from_registry("nvidia/cuda:12.4.1-devel-ubuntu22.04", add_python="3.11")
    .entrypoint([])
    .pip_install(
        "vllm==0.7.2",
        "huggingface_hub[hf_transfer]>=0.24.0",
        "hf-transfer>=0.1.8",
    )
    .env({
        "HF_HUB_ENABLE_HF_TRANSFER": "1",
        "PYTHONUNBUFFERED": "1",
    })
)

model_vol = modal.Volume.from_name(MODEL_VOLUME_NAME, create_if_missing=True)
hf_cache_vol = modal.Volume.from_name(HF_CACHE_VOLUME_NAME, create_if_missing=True)
vllm_cache_vol = modal.Volume.from_name(VLLM_CACHE_VOLUME_NAME, create_if_missing=True)


@app.function(
    image=image,
    timeout=60 * 30,
    volumes={MODEL_MOUNT: model_vol, HF_CACHE_MOUNT: hf_cache_vol},
)
def prefetch_model():
    """One-time (or occasional) prefetch to persist model weights on volume."""
    from huggingface_hub import snapshot_download

    print(f"[modal-qwen] prefetch start model={MODEL_ID} -> {MODEL_MOUNT}")
    snapshot_download(
        repo_id=MODEL_ID,
        local_dir=MODEL_MOUNT,
        local_dir_use_symlinks=False,
        resume_download=True,
    )
    model_vol.commit()
    hf_cache_vol.commit()
    print("[modal-qwen] prefetch complete")


@app.function(
    image=image,
    gpu="L4",
    timeout=60 * 60,
    scaledown_window=600,
    container_idle_timeout=600,
    requires_proxy_auth=True,
    volumes={
        MODEL_MOUNT: model_vol,
        HF_CACHE_MOUNT: hf_cache_vol,
        VLLM_CACHE_MOUNT: vllm_cache_vol,
    },
)
@modal.web_server(port=VLLM_PORT, startup_timeout=60 * 15)
def serve():
    """Run vLLM OpenAI-compatible server bound to a private Modal endpoint."""

    cmd = [
        "vllm",
        "serve",
        MODEL_MOUNT,
        "--host",
        "0.0.0.0",
        "--port",
        str(VLLM_PORT),
        "--served-model-name",
        MODEL_ID,
        "--download-dir",
        MODEL_MOUNT,
        "--max-model-len",
        "32768",
        "--gpu-memory-utilization",
        "0.90",
        "--enable-auto-tool-choice",
        "--tool-call-parser",
        "hermes",
    ]

    print("[modal-qwen] launching:", " ".join(cmd))
    subprocess.Popen(cmd)
