"""
Fase 3 del prototipo: puente HTTP local desechable para probar el modelo CRF
entrenado desde la app Flutter real (pantalla de diagnostico), sin tocar
infraestructura de produccion.

Ver prototypes/dictation_crf/README.md y la bitacora para el contexto completo.
Explicitamente un servidor de diagnostico: sin auth, CORS abierto, un solo
endpoint. No usar como base para el backend real (eso es decision de Alan).

Uso:
    .venv/bin/uvicorn server:app --host 0.0.0.0 --port 8000
"""

import pycrfsuite
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from crf_common import MODEL_PATH, reconstruct_items, sent2features, tokenize

app = FastAPI(title="Nexus — Prototipo dictado CRF (diagnostico)")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

_tagger = pycrfsuite.Tagger()
_tagger.open(str(MODEL_PATH))


class ParseRequest(BaseModel):
    text: str


class Item(BaseModel):
    qty: str
    name: str
    price: str


class ParseResponse(BaseModel):
    tokens: list[str]
    tags: list[str]
    items: list[Item]


@app.get("/health")
def health():
    return {"status": "ok", "model": str(MODEL_PATH.name)}


@app.post("/parse", response_model=ParseResponse)
def parse(req: ParseRequest):
    tokens = tokenize(req.text)
    if not tokens:
        return ParseResponse(tokens=[], tags=[], items=[])
    tags = _tagger.tag(sent2features(tokens))
    items = reconstruct_items(tokens, tags)
    return ParseResponse(tokens=tokens, tags=tags, items=items)
