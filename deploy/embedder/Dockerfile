FROM python:3.12-slim
WORKDIR /app

RUN pip install --no-cache-dir \
    fastapi>=0.110 \
    uvicorn>=0.27 \
    sentence-transformers>=2.6

COPY app.py .

# Pre-download model during build (cached in image)
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"

EXPOSE 8002

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8002"]
