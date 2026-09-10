# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación del módulo de expresiones regulares
import re
# Importación de tipado estático
from typing import Optional

# Importación de esquemas Pydantic
from app.modules.purchasing_suppliers.schemas.ocr_receipt import (
    VoiceDictationParseRequest,
    VoiceDictationParseResponse,
)


class VoiceParserService:
    """
    Servicio de interpretación semántica de dictado de voz nativo (SR-09 / Const. Art. 7.7).
    Convierte frases habladas en español mexicano en los 3 Campos Vitales de producto.
    """

    # Diccionario de números hablados en español
    NUMBER_WORDS = {
        "cero": 0, "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
        "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
        "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
        "dieciseis": 16, "dieciséis": 16, "diecisiete": 17, "dieciocho": 18, "diecinueve": 19,
        "veinte": 20, "veintiuno": 21, "veintidos": 22, "veintidós": 22, "veintitres": 23,
        "veintitrés": 23, "veinticuatro": 24, "veinticinco": 25, "veintiseis": 26,
        "veintiséis": 26, "veintisiete": 27, "veintiocho": 28, "veintinueve": 29,
        "treinta": 30, "cuarenta": 40, "cincuenta": 50, "sesenta": 60,
        "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100, "ciento": 100,
        "doscientos": 200, "trescientos": 300, "quinientos": 500, "mil": 1000,
    }

    def parse_voice_text(self, request: VoiceDictationParseRequest) -> VoiceDictationParseResponse:
        """
        Interpreta el texto dictado por voz y extrae Nombre, Precio MXN, Costo MXN y Stock.
        """
        text = request.voice_text.strip()
        cleaned_text = self._normalize_number_words(text)

        price: Optional[Decimal] = None
        cost: Optional[Decimal] = None
        stock: Decimal = Decimal("0.00")

        # 1. Extraer Precio (Campo Vital 2)
        # Patrones: "precio 38", "precio $38.50", "cuesta 38 pesos", "a 45 pesos"
        price_match = re.search(
            r"\b(?:precio|cuesta|valor|para venta)\s*(?:de)?\s*\$?(\d+(?:\.\d{1,2})?)\s*(?:pesos|mxn)?\b",
            cleaned_text,
            re.IGNORECASE,
        )
        if price_match:
            price = Decimal(price_match.group(1))
            cleaned_text = cleaned_text[:price_match.start()] + " " + cleaned_text[price_match.end():]
        else:
            # Buscar patrón "a 45 pesos"
            a_price_match = re.search(r"\ba\s+\$?(\d+(?:\.\d{1,2})?)\s*(?:pesos|mxn)\b", cleaned_text, re.IGNORECASE)
            if a_price_match:
                price = Decimal(a_price_match.group(1))
                cleaned_text = cleaned_text[:a_price_match.start()] + " " + cleaned_text[a_price_match.end():]
            else:
                sym_match = re.search(r"\$(\d+(?:\.\d{1,2})?)", cleaned_text)
                if sym_match:
                    price = Decimal(sym_match.group(1))
                    cleaned_text = cleaned_text[:sym_match.start()] + " " + cleaned_text[sym_match.end():]

        # 2. Extraer Costo opcional
        cost_match = re.search(
            r"\b(?:costo|me costo|me cost[oó]|compra)\s*(?:de)?\s*\$?(\d+(?:\.\d{1,2})?)\s*(?:pesos|mxn)?\b",
            cleaned_text,
            re.IGNORECASE,
        )
        if cost_match:
            cost = Decimal(cost_match.group(1))
            cleaned_text = cleaned_text[:cost_match.start()] + " " + cleaned_text[cost_match.end():]

        # 3. Extraer Existencias / Stock Inicial (Campo Vital 3)
        stock_match = re.search(
            r"\b(?:stock|cantidad|inventario|con|tengo|hay)\s*(?:de)?\s*(\d+(?:\.\d{1,2})?)\s*(?:piezas|pzas|pz|unidades|piez)?\b",
            cleaned_text,
            re.IGNORECASE,
        )
        if stock_match:
            stock = Decimal(stock_match.group(1))
            cleaned_text = cleaned_text[:stock_match.start()] + " " + cleaned_text[stock_match.end():]
        else:
            unit_match = re.search(r"\b(\d+(?:\.\d{1,2})?)\s*(?:piezas|pzas|unidades|pz)\b", cleaned_text, re.IGNORECASE)
            if unit_match:
                stock = Decimal(unit_match.group(1))
                cleaned_text = cleaned_text[:unit_match.start()] + " " + cleaned_text[unit_match.end():]

        # 4. Limpiar nombre resultante (Campo Vital 1)
        name = self._clean_product_name(cleaned_text)
        if not name:
            name = "Producto Dictado"

        # Si no se detectó precio explícito, asignar por defecto $0.00
        if price is None:
            price = Decimal("0.00")

        return VoiceDictationParseResponse(
            name=name,
            price_mxn=price.quantize(Decimal("0.01")),
            cost_mxn=cost.quantize(Decimal("0.01")) if cost is not None else None,
            initial_stock=stock.quantize(Decimal("0.01")),
            confidence=0.95 if price > 0 else 0.75,
        )

    def _normalize_number_words(self, text: str) -> str:
        """Reemplaza palabras de números en español por dígitos (ej: 'veinticuatro' -> '24')."""
        words = text.split()
        normalized_words = []
        for w in words:
            clean_w = w.lower().strip(",.")
            if clean_w in self.NUMBER_WORDS:
                normalized_words.append(str(self.NUMBER_WORDS[clean_w]))
            else:
                normalized_words.append(w)
        return " ".join(normalized_words)

    def _clean_product_name(self, text: str) -> str:
        """Limpia palabras de relleno comunes como 'agrega', 'nuevo', 'por favor'."""
        filler_words = [
            r"\b(?:agrega|agregar|registra|registrar|nuevo|nueva|crear|mete|pon)\b",
            r"\b(?:por favor|gracias|favor)\b",
            r"\b(?:pesos|pesitos|mxn)\b",
            r"\b(?:piezas|pzas|pz|unidades|piez)\b",
        ]
        res = text
        for pat in filler_words:
            res = re.sub(pat, " ", res, flags=re.IGNORECASE)
        # Quitar espacios redundantes y capitalizar
        res = re.sub(r"\s+", " ", res).strip()
        return res.title() if res else ""
