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

import os
import subprocess

import modal

APP_NAME = "private-modal-qwen35-9b"
MODEL_ID = "Qwen/Qwen3.5-9B"
MODEL_VOLUME_NAME = "private-modal-qwen35-9b-model"
HF_CACHE_VOLUME_NAME = "private-modal-qwen35-9b-hf-cache"
VLLM_CACHE_VOLUME_NAME = "private-modal-qwen35-9b-vllm-cache"
VLLM_PORT = 8000
MAX_MODEL_LEN = int(os.environ.get("MAX_MODEL_LEN", "16384"))
MAX_NUM_SEQS = int(os.environ.get("MAX_NUM_SEQS", "8"))
ENFORCE_EAGER = os.environ.get("ENFORCE_EAGER", "1") == "1"

MODEL_MOUNT = "/models"
HF_CACHE_MOUNT = "/root/.cache/huggingface"
VLLM_CACHE_MOUNT = "/root/.cache/vllm"


def model_cache_dir() -> str:
    return f"{MODEL_MOUNT}/{MODEL_ID.replace('/', '__')}"

app = modal.App(APP_NAME)

image = (
    modal.Image.from_registry("nvidia/cuda:12.4.1-devel-ubuntu22.04", add_python="3.11")
    .entrypoint([])
    .pip_install(
        # Qwen3.5-* uses the new qwen3_5 architecture, which requires newer
        # vLLM+transformers support than the old 0.7.2/4.48.x combo.
        "vllm==0.17.1",
        "transformers>=4.56.0,<5",
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
def prefetch_model(hf_token: str = ""):
    """One-time (or occasional) prefetch to persist model weights on volume."""
    from huggingface_hub import snapshot_download

    effective_token = hf_token or os.environ.get("HF_TOKEN") or os.environ.get("HUGGINGFACE_HUB_TOKEN", "")
    if effective_token:
        os.environ["HF_TOKEN"] = effective_token
        os.environ["HUGGINGFACE_HUB_TOKEN"] = effective_token

    model_path = model_cache_dir()
    print(f"[modal-qwen] prefetch start model={MODEL_ID} -> {model_path}; token={'yes' if effective_token else 'no'}")
    snapshot_download(
        repo_id=MODEL_ID,
        local_dir=model_path,
        local_dir_use_symlinks=False,
        resume_download=True,
        token=effective_token if effective_token else None,
    )
    model_vol.commit()
    hf_cache_vol.commit()
    print("[modal-qwen] prefetch complete")


@app.function(
    image=image,
    gpu="L4",
    timeout=60 * 60,
    scaledown_window=600,
    volumes={
        MODEL_MOUNT: model_vol,
        HF_CACHE_MOUNT: hf_cache_vol,
        VLLM_CACHE_MOUNT: vllm_cache_vol,
    },
)
@modal.web_server(port=VLLM_PORT, startup_timeout=60 * 15, requires_proxy_auth=True)
def serve():
    """Run vLLM OpenAI-compatible server bound to a private Modal endpoint."""

    model_path = model_cache_dir()

    cmd = [
        "vllm",
        "serve",
        MODEL_ID,
        "--host",
        "0.0.0.0",
        "--port",
        str(VLLM_PORT),
        "--served-model-name",
        MODEL_ID,
        "--download-dir",
        model_path,
        "--max-model-len",
        str(MAX_MODEL_LEN),
        "--max-num-seqs",
        str(MAX_NUM_SEQS),
        "--gpu-memory-utilization",
        "0.90",
        "--trust-remote-code",
        "--enable-auto-tool-choice",
        "--tool-call-parser",
        "hermes",
    ]

    if ENFORCE_EAGER:
        cmd.append("--enforce-eager")

    print("[modal-qwen] launching:", " ".join(cmd))
    subprocess.Popen(cmd)
