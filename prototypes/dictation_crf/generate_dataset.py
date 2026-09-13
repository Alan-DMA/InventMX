"""
Generador del dataset sintetico para el prototipo de dictado multi-item (CRFsuite).

Contexto completo del prototipo: docs/architecture/registro_implementacion.md,
seccion "EXPLORACION ACTIVA - Prototipo de dictado multi-item con CRFsuite".

Este script NO tiene dependencias externas (solo stdlib) a proposito: en esta
maquina no hay un interprete de Python con pip/venv funcional todavia (ver
README.md, seccion "Bloqueador de entorno"), asi que la Fase 1 (generar el
dataset) debia poder correr sin instalar nada.

Esquema de etiquetas (BIO):
  O           - palabra sin rol (verbos disparadores, preposiciones, "pesos", etc.)
  B-QTY/I-QTY - cantidad del item
  B-NAME/I-NAME - nombre del producto (puede ser multi-palabra)
  B-PRICE/I-PRICE - precio/costo del item
  B-SEP/I-SEP - conector que marca el INICIO DE UN ITEM NUEVO (ej. "tambien registra").
                Esta es la etiqueta clave del prototipo: en vez de segmentar como
                paso aparte (ej. dividiendo por regex de verbos), el modelo la
                aprende como una etiqueta mas de la misma secuencia.

Salida: data/dataset.json (lista de ejemplos) y data/dataset.conll (formato
token<TAB>tag, una oracion por bloque separado por linea en blanco - formato
estandar para entrenar con python-crfsuite en la Fase 2).
"""

import json
import random
from pathlib import Path

SEED = 20260913
random.seed(SEED)

OUT_DIR = Path(__file__).parent / "data"
OUT_DIR.mkdir(exist_ok=True)

# ---------------------------------------------------------------------------
# Vocabulario
# ---------------------------------------------------------------------------

# (nombre_producto_tokens, unidad_plausible)
PRODUCTS = [
    ("Coca Cola", "unidades"),
    ("Pepsi", "unidades"),
    ("agua Ciel", "botellas"),
    ("Sabritas", "bolsas"),
    ("Doritos", "bolsas"),
    ("leche Lala", "litros"),
    ("leche Nido", "botes"),
    ("yogurt Alpura", "unidades"),
    ("detergente Roma", "bolsas"),
    ("jabon Zote", "piezas"),
    ("arroz", "kilos"),
    ("frijol", "kilos"),
    ("aceite", "litros"),
    ("pan Bimbo", "paquetes"),
    ("Gansito", "piezas"),
    ("paracetamol", "cajas"),
    ("pasta blanca", "paquetes"),
    ("cerveza Corona", "latas"),
    ("chicles", "cajas"),
    ("cigarros", "cajetillas"),
    ("pilas doble A", "paquetes"),
    ("shampoo", "botellas"),
    ("cafe Nescafe", "frascos"),
    ("azucar", "kilos"),
    ("sal", "kilos"),
    ("huevo", "kilos"),
    ("tortillas", "kilos"),
    ("atun Dolores", "latas"),
    ("sardina", "latas"),
    ("galletas Marias", "paquetes"),
    ("chocolate Abuelita", "cajas"),
    ("papel higienico", "paquetes"),
    ("refresco de manzana", "unidades"),
    ("harina PAN", "kilos"),
    # Nombres con "de" adentro del propio nombre (no como conector unidad->
    # nombre) - encontrado como hueco real al validar con Eduardo: el modelo
    # solo habia visto "de" como frontera fija, nunca como parte del nombre
    # (ej. "figuritas de mario"). Estos generan "... de pan de dulce", con
    # dos "de" seguidos: el conector + el que es parte del nombre.
    ("pan de dulce", "paquetes"),
    ("salsa de tomate", "botellas"),
    ("sopa de pasta", "paquetes"),
    ("agua de jamaica", "litros"),
    ("aceite de oliva", "litros"),
    ("pasta de dientes", "piezas"),
    ("crema de cacahuate", "frascos"),
]

UNIT_SINGULAR = {
    "unidades": "unidad", "botellas": "botella", "bolsas": "bolsa",
    "litros": "litro", "botes": "bote", "piezas": "pieza", "kilos": "kilo",
    "paquetes": "paquete", "latas": "lata", "cajas": "caja",
    "cajetillas": "cajetilla", "frascos": "frasco",
}

TRIGGER_VERBS = ["registra", "anota", "agrega", "apunta", "mete", "captura"]

CONNECTORS = [
    "tambien",
    "y tambien",
    "ademas",
    "y",
    "y de una vez",
    "y de paso",
]

QTY_WORDS = {
    1: "uno", 2: "dos", 3: "tres", 4: "cuatro", 5: "cinco",
    6: "seis", 7: "siete", 8: "ocho", 9: "nueve", 10: "diez",
    11: "once", 12: "doce", 15: "quince", 20: "veinte",
    22: "veintidos", 25: "veinticinco",
}

PRICE_TEMPLATES = [
    "con un costo de {price} pesos",
    "a {price} pesos",
    "que cuestan {price} pesos",
    "por {price} pesos cada uno",
    "a {price} pesos la pieza",
    "con un precio de {price} pesos",
    "por un precio de {price} pesos",
    "al precio de {price} pesos",
]

# Nombres genericos en plural, usados por la variante "sin unidad ni 'de'"
# (ver GAP_NO_UNIT_PROB mas abajo) - ej. "5 chocolates a 8 pesos", sin
# "piezas de" en medio. No tiene sentido pluralizar marcas especificas
# ("5 Coca Colas") de forma generica, asi que esta variante usa su propio
# vocabulario mas coloquial en vez de PRODUCTS.
GENERIC_PLURAL_PRODUCTS = [
    "chocolates", "refrescos", "galletas", "jabones", "dulces", "yogures",
    "chicles", "cervezas", "aguas", "papitas",
]

# Igual que arriba pero multi-palabra - hueco real encontrado al validar con
# Eduardo: "30 tornillos cabeza plana a 30 pesos" etiqueto "cabeza" como
# B-QTY en vez de I-NAME. Causa: la variante sin unidad/"de" solo tenia
# nombres de una palabra, asi que el modelo nunca vio un I-NAME continuar
# sin que antes hubiera un "de". Con esta lista aprende que el nombre puede
# seguir siendo multi-palabra aun sin "de" por delante.
GENERIC_PLURAL_MULTIWORD = [
    "tornillos cabeza plana", "focos ahorradores", "pilas alcalinas",
    "bolsas negras", "cubetas plasticas", "franelas amarillas",
    "candados chicos", "clavos punta fina", "guantes negros",
    "cinta canela",
]

# Probabilidad de generar el item sin "unidad de" (ej. "5 chocolates a 8
# pesos" en vez de "5 piezas de chocolate a 8 pesos") - todas las plantillas
# originales siempre incluian "de", lo que dejaba un hueco de generalizacion
# encontrado al validar la Fase 2 contra frases escritas a mano (ver README).
GAP_NO_UNIT_PROB = 0.2

# Probabilidad de generar el item SIN cantidad en absoluto (ej. "figuritas
# de mario por un precio de 20 pesos", sin numero) - otro hueco real: todos
# los items de entrenamiento tenian exactamente un B-QTY, asi que el modelo
# nunca habia visto la posicion "justo despues del verbo" sin un digito ahi,
# y confundia la primera palabra del nombre con la palabra-unidad.
SKIP_QTY_PROB = 0.15

# ---------------------------------------------------------------------------
# Helpers de construccion de tokens+tags
# ---------------------------------------------------------------------------


def tag_span(tokens_text, tag_name):
    """Devuelve lista de (token, tag) con esquema B-/I- para una lista de tokens."""
    out = []
    for i, tok in enumerate(tokens_text.split(" ")):
        prefix = "B-" if i == 0 else "I-"
        out.append((tok, f"{prefix}{tag_name}"))
    return out


def make_qty_tokens(qty):
    if qty in QTY_WORDS and random.random() < 0.3:
        return tag_span(QTY_WORDS[qty], "QTY")
    return tag_span(str(qty), "QTY")


def make_price_tokens(price):
    if price in QTY_WORDS and random.random() < 0.15:
        return tag_span(QTY_WORDS[price], "PRICE")
    return tag_span(str(price), "PRICE")


def make_item(is_first, include_comma):
    """Construye un item completo: [SEP opcional] verbo qty unidad de NOMBRE precio-frase."""
    product_name, unit = random.choice(PRODUCTS)
    qty = random.choice([1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 22, 25])
    price = random.choice([5, 8, 10, 12, 15, 16, 18, 20, 25, 30, 35, 45, 50,
                            60, 75, 80, 100, 120, 150, 180, 200, 250, 300, 500])

    tokens = []

    if not is_first:
        if include_comma:
            tokens.append((",", "O"))
        connector = random.choice(CONNECTORS)
        verb = random.choice(TRIGGER_VERBS)
        # El conector + verbo repetido forman el span B-SEP/I-SEP:
        # es la señal explicita de "aqui empieza un item nuevo".
        sep_text = f"{connector} {verb}" if random.random() < 0.7 else connector
        tokens.extend(tag_span(sep_text, "SEP"))
    else:
        verb = random.choice(TRIGGER_VERBS)
        tokens.append((verb, "O"))

    if random.random() < SKIP_QTY_PROB:
        # Sin cantidad: directo al nombre, sin unidad ni "de".
        tokens.extend(tag_span(product_name, "NAME"))
    else:
        tokens.extend(make_qty_tokens(qty))

        if qty > 1 and random.random() < GAP_NO_UNIT_PROB:
            # Variante sin "unidad de": "5 chocolates a 8 pesos" o, la mitad
            # de las veces, su version multi-palabra "30 tornillos cabeza
            # plana a 30 pesos" (ver GENERIC_PLURAL_MULTIWORD).
            pool = GENERIC_PLURAL_MULTIWORD if random.random() < 0.5 else GENERIC_PLURAL_PRODUCTS
            product_name = random.choice(pool)
            tokens.extend(tag_span(product_name, "NAME"))
        else:
            unit_word = UNIT_SINGULAR[unit] if qty == 1 else unit
            tokens.append((unit_word, "O"))
            tokens.append(("de", "O"))
            tokens.extend(tag_span(product_name, "NAME"))

    # Tokenizar la plantilla de precio palabra por palabra, e insertar en el
    # hueco del placeholder los tokens del valor (puede ser multi-token si el
    # numero viene deletreado, ej. "veinticinco").
    price_value_tokens = make_price_tokens(price)
    template = random.choice(PRICE_TEMPLATES)
    before, after = template.split("{price}")
    before_words = [w for w in before.strip().split(" ") if w]
    after_words = [w for w in after.strip().split(" ") if w]

    for w in before_words:
        tokens.append((w, "O"))
    tokens.extend(price_value_tokens)
    for w in after_words:
        tokens.append((w, "O"))

    return tokens


def make_sentence():
    n_items = random.choices([1, 2, 3], weights=[0.2, 0.5, 0.3])[0]
    tokens = []
    for i in range(n_items):
        include_comma = random.random() < 0.4
        tokens.extend(make_item(is_first=(i == 0), include_comma=include_comma))
    return tokens


def capitalize_first(tokens):
    if not tokens:
        return tokens
    first_tok, first_tag = tokens[0]
    tokens[0] = (first_tok[0].upper() + first_tok[1:], first_tag)
    return tokens


# ---------------------------------------------------------------------------
# Generacion del dataset
# ---------------------------------------------------------------------------

N_EXAMPLES = 480

examples = []
seen_texts = set()

attempts = 0
while len(examples) < N_EXAMPLES and attempts < N_EXAMPLES * 20:
    attempts += 1
    tokens = make_sentence()
    tokens = capitalize_first(tokens)
    text = " ".join(t for t, _ in tokens)
    if text in seen_texts:
        continue
    seen_texts.add(text)
    examples.append(
        {
            "id": len(examples) + 1,
            "text": text,
            "tokens": [t for t, _ in tokens],
            "tags": [tag for _, tag in tokens],
        }
    )

# ---------------------------------------------------------------------------
# Escritura de salidas
# ---------------------------------------------------------------------------

json_path = OUT_DIR / "dataset.json"
with json_path.open("w", encoding="utf-8") as f:
    json.dump(examples, f, ensure_ascii=False, indent=2)

conll_path = OUT_DIR / "dataset.conll"
with conll_path.open("w", encoding="utf-8") as f:
    for ex in examples:
        for tok, tag in zip(ex["tokens"], ex["tags"]):
            f.write(f"{tok}\t{tag}\n")
        f.write("\n")

# ---------------------------------------------------------------------------
# Resumen de sanity-check
# ---------------------------------------------------------------------------

tag_counts = {}
item_count_hist = {}
for ex in examples:
    n_items = sum(1 for t in ex["tags"] if t == "B-SEP") + 1
    item_count_hist[n_items] = item_count_hist.get(n_items, 0) + 1
    for tag in ex["tags"]:
        base = tag.split("-", 1)[-1] if tag != "O" else "O"
        tag_counts[base] = tag_counts.get(base, 0) + 1

print(f"Ejemplos generados: {len(examples)}")
print(f"Distribucion de items por oracion: {dict(sorted(item_count_hist.items()))}")
print(f"Conteo de tags (por tipo de campo): {tag_counts}")
print(f"Escrito: {json_path}")
print(f"Escrito: {conll_path}")
print()
print("Muestra (3 ejemplos aleatorios):")
for ex in random.sample(examples, 3):
    print(f"  [{ex['id']}] {ex['text']}")
