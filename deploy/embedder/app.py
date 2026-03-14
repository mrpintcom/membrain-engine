"""Embedder sidecar — exposes sentence-transformers as an HTTP service."""

import asyncio
import logging
from contextlib import asynccontextmanager
from functools import lru_cache

from fastapi import FastAPI
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("embedder")

MODEL_NAME = "all-MiniLM-L6-v2"


@lru_cache(maxsize=1)
def _load_model():
    from sentence_transformers import SentenceTransformer

    logger.info("Loading model: %s", MODEL_NAME)
    model = SentenceTransformer(MODEL_NAME)
    logger.info("Model loaded")
    return model


@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_model()  # Warm up on startup
    yield


app = FastAPI(title="Membrain Embedder", lifespan=lifespan)


class EmbedRequest(BaseModel):
    text: str = Field(..., max_length=10000)


class EmbedResponse(BaseModel):
    embedding: list[float]


@app.post("/embed", response_model=EmbedResponse)
async def embed(req: EmbedRequest):
    model = _load_model()
    loop = asyncio.get_running_loop()
    vector = await loop.run_in_executor(None, lambda: model.encode(req.text).tolist())
    return EmbedResponse(embedding=vector)


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL_NAME}
