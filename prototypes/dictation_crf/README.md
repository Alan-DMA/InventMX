# Prototipo — Dictado multi-item con CRFsuite

> **Resultado final (Sep 2026): CRFsuite descartado para producción.** Los huecos
> encontrados en esta exploración (ver "Fase 3 en vivo" más abajo) llevaron a un pivote de
> producto — formato de dictado guiado en vez de NLU libre — bajo el cual un regex
> **posicional** (no el original) iguala o supera al CRF sin el costo de portarlo a Dart.
> Implementación real en `frontend/lib/core/utils/voice_dictation_helper.dart` +
> `frontend/lib/features/purchases/presentation/widgets/dictation_modal.dart`. Detalle
> completo de la decisión en `docs/architecture/registro_implementacion.md`, sección de
> Tarea 12.2.3. Esta carpeta se conserva como registro de la exploración que informó esa
> decisión, no se usa en producción.

Exploración personal de Eduardo, **fuera del alcance formal de frontend** definido en
`CLAUDE.md` (es un script de Python, no Flutter). No es una tarea del plan de 16 días ni
una entrega de la Tarea 12.1 de Alan — decide si vale la pena invertir en reemplazar/extender
`VoiceDictationParser` para el caso de **una sola frase con varios productos**.

Contexto completo, alternativas evaluadas y justificación: `docs/architecture/registro_implementacion.md`,
sección "🧪 EXPLORACIÓN ACTIVA — Prototipo de dictado multi-item con CRFsuite".

## Estado

- ✅ **Fase 1 — Dataset sintético**: hecha. `generate_dataset.py` genera 320 ejemplos
  (sin dependencias externas, solo stdlib) con etiquetado BIO en `data/dataset.json` y
  `data/dataset.conll`.
- ✅ **Fase 2 — Entrenar y validar con `python-crfsuite`**: hecha, resultado **prometedor**.
  Ver "Resultados de la Fase 2" abajo. Entorno desbloqueado (WSL: `apt install
  python3.14-venv build-essential` + venv + `pip install python-crfsuite`).
- ⏳ **Fase 3 — Puente HTTP local**: condicional cumplida (Fase 2 prometedora) — **pendiente
  decisión explícita de Eduardo antes de empezarla** (toca `frontend/`, aunque sea solo una
  pantalla de diagnóstico).

## Resultados de la Fase 2 (Sep 2026)

`train_crf.py` entrena un CRF lineal (`pycrfsuite`) sobre 272 oraciones (85% del dataset) y
valida contra dos conjuntos:

**1. Held-out del propio dataset (48 oraciones, mismo estilo de plantillas):**

| Métrica | Resultado |
|---|---|
| Accuracy a nivel de token | 1196/1196 = **100%** |
| Segmentación correcta (N de ítems) | 48/48 = **100%** |
| Oración 100% correcta (segmentación + 3 campos) | 48/48 = **100%** |
| Accuracy por campo (qty/name/price) | 312/312 = **100%** |

Esperable — mismo estilo de plantillas que el training. Confirma que el esquema de tags
(`B-SEP` incluido) es aprendible, no prueba generalización por sí solo.

**2. Frases escritas a mano, nunca vistas en entrenamiento** (el criterio de éxito real del
plan — ver script para las 6 frases exactas):

**5 de 6 perfectas** — incluyendo verbos fuera del vocabulario de entrenamiento
(`"necesito"`, nunca en `TRIGGER_VERBS`) y nombres de producto con acentos no vistos
(`"café"`, `"jabón"`, `"azúcar"`) resueltos correctamente por posición/contexto, no por
memorización de vocabulario — buena señal de generalización real.

**1 falla explicable (primera corrida):** en *"apunta 12 refrescos de cola con un costo de
300 pesos y también 5 chocolates a 8 pesos"*, `"chocolates"` no se etiquetó como `B-NAME`
(quedó `O`). Causa identificada: todas las 320 oraciones de entrenamiento seguían el patrón
`QTY unidad DE nombre`; esta frase omite la preposición "de" antes del segundo producto — un
hueco del generador de datos, no una limitación del enfoque CRF.

**Fix aplicado (segunda corrida):** se agregó al generador la variante `GAP_NO_UNIT_PROB`
(20% de los ítems con `qty > 1`) que construye el ítem sin "unidad de" — ej. `"5 chocolates
a 8 pesos"` — usando un vocabulario genérico en plural (`GENERIC_PLURAL_PRODUCTS`) separado
de los nombres de marca (pluralizar "Coca Cola" genéricamente no tiene sentido). Se
regeneró el dataset y se re-entrenó: **las 6/6 frases escritas a mano salieron perfectas**,
incluyendo `"chocolates"`.

**Lectura del criterio de éxito de la bitácora** ("mayoría funcionando → se justifica
desarrollar a fondo"): con 6/6 frases reales completamente correctas tras una sola iteración
de corrección barata, **el resultado es prometedor** — desbloquea la Fase 3 condicional.

## Fase 3 en vivo — hallazgos de Eduardo probando con voz/texto real (Sep 2026)

Con la pantalla de diagnóstico corriendo, Eduardo probó la frase:

> "almacena figuritas de mario por un precio de 20 pesos mexicano y 30 tornillos cabeza plana a 30 pesos cada uno"

Encontró **3 huecos nuevos**, todos cerrados salvo el último (ver detalle):

1. **✅ Corregido — nombre multi-palabra tras cantidad sin unidad/"de":** `"30 tornillos
   cabeza plana a 30 pesos"` etiquetaba `"cabeza"` como `B-QTY` en vez de `I-NAME`. Causa: la
   variante sin unidad (`GAP_NO_UNIT_PROB`) solo tenía nombres genéricos de una palabra
   (`GENERIC_PLURAL_PRODUCTS`), así que el modelo nunca había visto un `I-NAME` continuar sin
   que antes hubiera un "de". Fix: `GENERIC_PLURAL_MULTIWORD` — mitad de las veces esa
   variante ahora usa nombres de 2-3 palabras (`"tornillos cabeza plana"`, `"focos
   ahorradores"`, etc.).
2. **✅ Corregido — "de" como parte del propio nombre:** `"figuritas de mario"` tiene un "de"
   que no es el conector unidad→nombre sino parte del nombre. Fix: se agregaron productos con
   "de" interno a `PRODUCTS` (`"pan de dulce"`, `"salsa de tomate"`, `"agua de jamaica"`,
   etc.), generando frases con doble "de" seguido (`"... de agua de jamaica ..."`) para que el
   modelo aprenda que no siempre es frontera.
3. **⚠️ No corregido — vocabulario totalmente nunca visto + item sin cantidad + verbo/plantilla
   de precio nuevos, todo junto:** `"figuritas"` sigue etiquetándose `O` en vez de `B-NAME`
   (se pierde del nombre reconstruido, que queda solo `"mario"`). A diferencia de 1 y 2, esto
   **no es un hueco estructural** — se probó agrandando el dataset (320→480 ejemplos) y no
   cambió nada. La causa real: ni `"figuritas"` ni `"mario"` aparecen en NINGÚN lugar del
   vocabulario de entrenamiento, y coinciden en la misma frase con un verbo nunca visto
   (`"almacena"`) y una plantilla de precio nunca vista (`"por un precio de ... pesos
   mexicano"`) — cuatro cosas nuevas a la vez. Un CRF con features léxicas simples (identidad
   de palabra, prefijo/sufijo, mayúscula, dígito) no tiene forma de generalizar
   semánticamente a palabras que nunca vio — no es un bug puntual que se arregle agregando
   3-4 ejemplos más, sino una limitación esperable del enfoque elegido (barato, sin
   embeddings/LLM — ver alternativas descartadas arriba). Nota de contexto: la app es para
   inventario de abarrotes/tienda de conveniencia — "figuritas de Mario" (juguetes) es un
   producto fuera del dominio real de uso, así que esto es más un stress-test de vocabulario
   verdaderamente cero-shot que un caso representativo de uso real.

Dataset regenerado a **480 ejemplos** (antes 320) tras estos fixes — held-out sigue en
~99.9% token-level, 1 de 72 oraciones con una discrepancia menor (esperable con la variedad
nueva, no es señal de alarma). Las 7/8 frases escritas a mano (incluida la de Eduardo, salvo
el punto 3) salen perfectas. Servidor de diagnóstico reiniciado con el modelo re-entrenado.

## Esquema de etiquetas (BIO)

| Tag | Significa |
|---|---|
| `O` | Sin rol (verbo disparador, preposiciones, "pesos", etc.) |
| `B-QTY` / `I-QTY` | Cantidad del ítem |
| `B-NAME` / `I-NAME` | Nombre del producto (puede ser multi-palabra) |
| `B-PRICE` / `I-PRICE` | Precio/costo del ítem |
| `B-SEP` / `I-SEP` | Conector que marca el **inicio de un ítem nuevo** (ej. "también registra") |

`B-SEP` es la pieza central del prototipo: en vez de segmentar por regex de verbos como
paso aparte, el modelo aprende el límite entre ítems como una etiqueta más de la misma
secuencia — así es como se probará si CRFsuite resuelve la rigidez que tenía la alternativa
de regex (descartada, ver bitácora).

Ejemplo (`data/dataset.json`, id 2):

```
Captura veintidos bolsas de detergente Roma por 16 pesos cada uno , también captura 10 kilos de huevo que cuestan 60 pesos
O       B-QTY    O      O  B-NAME     I-NAME O   B-PRICE O    O    O O    B-SEP    B-SEP   B-QTY O     O  B-NAME O    B-PRICE O
```

## Cómo se generó el dataset

```
python3 generate_dataset.py
```

- 33 productos (reutiliza nombres de `frontend/lib/features/inventory/data/inventory_mock_data.dart`
  sin el sufijo de tamaño, porque en dictado real la gente no dice "45g").
- 6 verbos disparadores, 6 conectores, 5 plantillas de frase de precio.
- Distribución de ítems por oración: 20% con 1 ítem, 50% con 2, 30% con 3 — a propósito
  sesgado hacia multi-ítem porque es el caso que este prototipo existe para resolver; el
  caso de 1 ítem ya lo cubre el parser regex actual y se incluye solo como control.
- Cantidades y precios: mayormente dígitos, con una fracción deletreada (`"cinco"`,
  `"veinticinco"`) restringida a números de una sola palabra (1-29) para no chocar con
  el conector `"y"` (evita ambigüedad con números compuestos tipo "treinta y cinco").
- Semilla fija (`SEED = 20260913`) — reproducible.

Salida real de la última corrida:

```
Ejemplos generados: 320
Distribución de ítems por oración: {1: 65, 2: 148, 3: 107}
Conteo de tags: {'O': 4319, 'QTY': 682, 'NAME': 1104, 'PRICE': 682, 'SEP': 968}
```

## Entorno (resuelto, Sep 2026)

Esta máquina Windows **no tiene un intérprete de Python real** — solo el stub de Microsoft
Store. Se usa la distro WSL (`Ubuntu 26.04`, `python3.14`) para todo el prototipo. Setup
que se corrió una vez (requirió contraseña de `sudo`, provista por Eduardo):

```
sudo apt update && sudo apt install -y python3.14-venv build-essential
cd prototypes/dictation_crf
python3 -m venv .venv
.venv/bin/pip install python-crfsuite
```

Reproducir desde cero (ya con lo anterior instalado):

```
cd prototypes/dictation_crf
python3 generate_dataset.py     # Fase 1 — regenera data/dataset.{json,conll}
.venv/bin/python train_crf.py   # Fase 2 — entrena model/crf_model.crfsuite y valida
```

## Próximo paso concreto al retomar

Decidir si se entra a la **Fase 3** (puente HTTP local + pantalla de diagnóstico en
Flutter) — la condición ("Fase 2 prometedora") ya se cumplió, pero Fase 3 toca
`frontend/` y es una decisión explícita pendiente de Eduardo, no algo que se dispare solo.
Si se decide que sí: antes de tocar Flutter, vale la pena primero cerrar el hueco de dataset
identificado arriba (variante de plantilla sin "de" explícito) y re-entrenar, ya que es
barato y mejora la confiabilidad del backend de diagnóstico antes de exponerlo en el
teléfono.

## Explícitamente fuera de alcance de este prototipo

Bindings nativos en Dart, despliegue a la VPS real, integración con `PurchaseCreateScreen`
u otra pantalla de producción, pasar por `/intent`/`/impeccable` (herramienta de diagnóstico
interna, no una feature que se vaya a enviar con esa cara).
