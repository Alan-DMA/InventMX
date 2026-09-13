"""
Fase 2 del prototipo: entrenar un CRF lineal (python-crfsuite) sobre el dataset
sintetico de la Fase 1 y validarlo, tanto con un held-out del propio dataset como
con frases inventadas a mano que el modelo nunca vio.

Ver prototypes/dictation_crf/README.md y la bitacora para el contexto completo.

Uso:
    .venv/bin/python train_crf.py
"""

import random
from pathlib import Path

import pycrfsuite

from crf_common import MODEL_PATH, reconstruct_items, sent2features, tokenize

DATA_DIR = Path(__file__).parent / "data"
MODEL_PATH.parent.mkdir(exist_ok=True)

SEED = 20260913
random.seed(SEED)

# ---------------------------------------------------------------------------
# Carga del dataset (.conll -> lista de (tokens, tags))
# ---------------------------------------------------------------------------


def load_conll(path):
    sentences = []
    tokens, tags = [], []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                if tokens:
                    sentences.append((tokens, tags))
                    tokens, tags = [], []
                continue
            tok, tag = line.split("\t")
            tokens.append(tok)
            tags.append(tag)
    if tokens:
        sentences.append((tokens, tags))
    return sentences


# ---------------------------------------------------------------------------
# Entrenamiento
# ---------------------------------------------------------------------------


def main():
    sentences = load_conll(DATA_DIR / "dataset.conll")
    random.shuffle(sentences)

    split = int(len(sentences) * 0.85)
    train_sents = sentences[:split]
    test_sents = sentences[split:]

    print(f"Total oraciones: {len(sentences)} | train: {len(train_sents)} | test: {len(test_sents)}")

    trainer = pycrfsuite.Trainer(verbose=False)
    for tokens, tags in train_sents:
        trainer.append(sent2features(tokens), tags)

    trainer.set_params(
        {
            "c1": 0.1,  # regularizacion L1
            "c2": 0.1,  # regularizacion L2
            "max_iterations": 100,
            "feature.possible_transitions": True,
        }
    )
    trainer.train(str(MODEL_PATH))
    print(f"Modelo entrenado: {MODEL_PATH}")

    tagger = pycrfsuite.Tagger()
    tagger.open(str(MODEL_PATH))

    # --- Evaluacion token-level sobre el held-out ---
    total_tokens = 0
    correct_tokens = 0
    for tokens, gold_tags in test_sents:
        pred_tags = tagger.tag(sent2features(tokens))
        for g, p in zip(gold_tags, pred_tags):
            total_tokens += 1
            if g == p:
                correct_tokens += 1

    print(f"\nAccuracy a nivel de token (held-out, {len(test_sents)} oraciones): "
          f"{correct_tokens}/{total_tokens} = {correct_tokens / total_tokens:.4f}")

    # --- Evaluacion a nivel de item (segmentacion + 3 campos correctos) ---
    exact_sentence_matches = 0
    item_count_matches = 0
    field_correct = 0
    field_total = 0

    for tokens, gold_tags in test_sents:
        pred_tags = tagger.tag(sent2features(tokens))
        gold_items = reconstruct_items(tokens, gold_tags)
        pred_items = reconstruct_items(tokens, pred_tags)

        if len(gold_items) == len(pred_items):
            item_count_matches += 1

        if gold_items == pred_items:
            exact_sentence_matches += 1

        for gi, pi in zip(gold_items, pred_items):
            for field in ("qty", "name", "price"):
                field_total += 1
                if gi[field] == pi[field]:
                    field_correct += 1

    n_test = len(test_sents)
    print(f"Oraciones con N de items correcto (segmentacion): {item_count_matches}/{n_test} "
          f"= {item_count_matches / n_test:.4f}")
    print(f"Oraciones 100% correctas (segmentacion + 3 campos exactos): "
          f"{exact_sentence_matches}/{n_test} = {exact_sentence_matches / n_test:.4f}")
    if field_total:
        print(f"Accuracy por campo (qty/name/price, sobre items alineados): "
              f"{field_correct}/{field_total} = {field_correct / field_total:.4f}")

    # --- Frases inventadas a mano (fuera del dataset, criterio de exito del plan) ---
    print("\n" + "=" * 70)
    print("VALIDACION CON FRASES ESCRITAS A MANO (no vistas en entrenamiento)")
    print("=" * 70)

    hand_written = [
        "registra 5 unidades de paracetamol con un costo de 500 pesos, también registra 10 unidades de pasta blanca con un costo de 200 pesos",
        "anota 3 kilos de arroz a 25 pesos y 2 litros de aceite a 45 pesos",
        "agrega 6 latas de atun que cuestan 18 pesos",
        "captura 1 kilo de café por 150 pesos, también mete 4 piezas de jabón a 12 pesos, y agrega 2 kilos de azúcar a 20 pesos",
        "necesito 8 bolsas de papitas a 15 pesos",
        "apunta 12 refrescos de cola con un costo de 300 pesos y también 5 chocolates a 8 pesos",
        # Frase real de Eduardo (Sep 2026): reveló el hueco de nombres
        # multi-palabra tras cantidad sin unidad/"de" ("cabeza" se leía como
        # B-QTY en vez de I-NAME) y el caso de "de" dentro del propio nombre
        # ("figuritas de mario"). Ver bitácora.
        "almacena figuritas de mario por un precio de 20 pesos mexicano y 30 tornillos cabeza plana a 30 pesos cada uno",
    ]

    for phrase in hand_written:
        tokens = tokenize(phrase)
        pred_tags = tagger.tag(sent2features(tokens))
        items = reconstruct_items(tokens, pred_tags)
        print(f"\n> {phrase}")
        for tok, tag in zip(tokens, pred_tags):
            print(f"    {tok:20s} {tag}")
        print(f"  -> Items reconstruidos: {items}")


if __name__ == "__main__":
    main()
