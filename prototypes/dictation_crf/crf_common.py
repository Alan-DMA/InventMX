"""
Piezas compartidas entre train_crf.py (Fase 2) y server.py (Fase 3):
extraccion de features y reconstruccion de items a partir de tokens+tags.
Separado para que el servidor de diagnostico no duplique la logica de
entrenamiento/evaluacion.
"""

from pathlib import Path

MODEL_PATH = Path(__file__).parent / "model" / "crf_model.crfsuite"


def word_features(word):
    return {
        "word.lower": word.lower(),
        "word.isdigit": word.isdigit(),
        "word.istitle": word.istitle(),
        "word[-3:]": word[-3:],
        "word[:3]": word[:3],
        "word.is_connector": word.lower() in {"tambien", "y", "ademas", "de"},
    }


def sent2features(tokens):
    feats_per_token = []
    n = len(tokens)
    for i, word in enumerate(tokens):
        feats = {f"w.{k}": v for k, v in word_features(word).items()}
        feats["BOS"] = i == 0
        feats["EOS"] = i == n - 1

        if i > 0:
            prev = word_features(tokens[i - 1])
            feats.update({f"-1:{k}": v for k, v in prev.items()})
        if i > 1:
            prev2 = word_features(tokens[i - 2])
            feats.update({f"-2:{k}": v for k, v in prev2.items()})
        if i < n - 1:
            nxt = word_features(tokens[i + 1])
            feats.update({f"+1:{k}": v for k, v in nxt.items()})
        if i < n - 2:
            nxt2 = word_features(tokens[i + 2])
            feats.update({f"+2:{k}": v for k, v in nxt2.items()})

        feats_per_token.append(feats)
    return feats_per_token


def reconstruct_items(tokens, tags):
    """Reconstruye la lista de items (segmentacion + 3 campos) a partir de
    tokens+tags. B-SEP marca el limite entre items — es la etiqueta clave
    que el prototipo evalua."""
    items = []
    current = {"qty": [], "name": [], "price": []}

    def flush():
        if current["qty"] or current["name"] or current["price"]:
            items.append(
                {
                    "qty": " ".join(current["qty"]),
                    "name": " ".join(current["name"]),
                    "price": " ".join(current["price"]),
                }
            )

    for tok, tag in zip(tokens, tags):
        if tag == "B-SEP":
            flush()
            current = {"qty": [], "name": [], "price": []}
        elif tag == "I-SEP" or tag == "O":
            continue
        else:
            field = tag.split("-", 1)[1].lower()
            if field in ("qty", "name", "price"):
                current[field].append(tok)
    flush()
    return items


def tokenize(text):
    """Tokenizador simple y consistente con el usado para generar el dataset
    y para las frases de validacion escritas a mano: separa comas como token
    propio, resto por espacios."""
    text = text.replace(",", " , ")
    return [t for t in text.split() if t]
