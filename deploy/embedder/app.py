"""Membrain Embedder Sidecar — serves sentence-transformer embeddings via HTTP."""

import asyncio
from functools import lru_cache

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI(title="Membrain Embedder")

MODEL_NAME = "all-MiniLM-L6-v2"


@lru_cache(maxsize=1)
def _load_model():
    from sentence_transformers import SentenceTransformer
    return SentenceTransformer(MODEL_NAME)


class EmbedRequest(BaseModel):
    text: str


class EmbedResponse(BaseModel):
    embedding: list[float]
    dimension: int


@app.post("/embed", response_model=EmbedResponse)
async def embed(req: EmbedRequest):
    model = _load_model()
    loop = asyncio.get_running_loop()
    vector = await loop.run_in_executor(
        None, lambda: model.encode(req.text).tolist()
    )
    return EmbedResponse(embedding=vector, dimension=len(vector))


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL_NAME}