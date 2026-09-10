# Importación de precisión decimal para Pesos Mexicanos
from decimal import Decimal
# Importación de algoritmo de similitud difusa de cadenas
import difflib
# Importación del módulo de expresiones regulares
import re
# Importación de tipado estático
from typing import List, Optional, Tuple
# Importación de identificadores únicos UUID
import uuid

# Importación de componentes de SQLAlchemy asíncrono
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# Importación de entidades de dominio
from app.modules.auth_tenancy.domain.user import User
from app.modules.inventory.domain.product import Product
from app.modules.purchasing_suppliers.domain.supplier import Supplier
# Importación de esquemas Pydantic
from app.modules.purchasing_suppliers.schemas.ocr_receipt import (
    ReceiptOcrItemResponse,
    ReceiptOcrParseRequest,
    ReceiptOcrParseResponse,
)


class ReceiptParserService:
    """
    Servicio de parseo heurístico de facturas y notas de remisión físicas (RF-28 / Const. Art. 4.2, 7.7).
    Funciona 100% offline en el backend sin depender de APIs cloud de pago (Principio Bootstrap).
    """

    def __init__(self, session: AsyncSession) -> None:
        # Inyección de la sesión asíncrona de base de datos
        self.session = session

    async def parse_receipt_text(
        self,
        request: ReceiptOcrParseRequest,
        current_user: User,
    ) -> ReceiptOcrParseResponse:
        """
        Interpreta el texto plano extraído de una factura/remisión física y empareja
        los productos detectados con el catálogo existente del comercio.
        """
        # Obtener el texto plano extraído en el cliente
        raw_text = request.raw_text
        # Dividir en líneas no vacías
        lines = [line.strip() for line in raw_text.splitlines() if line.strip()]

        # 1. Detectar proveedor o distribuidora
        supplier_name = await self._detect_supplier_name(lines, request.supplier_id, current_user.tenant_id)

        # 2. Detectar folio o número de factura
        invoice_reference = self._detect_invoice_reference(lines)

        # 3. Cargar catálogo de productos activos del comercio para emparejamiento difuso
        catalog_products = await self._load_tenant_products(current_user.tenant_id)

        # 4. Parsear líneas de productos
        parsed_items: List[ReceiptOcrItemResponse] = []
        total_sum = Decimal("0.00")
        unmatched_count = 0

        for line in lines:
            # Intentar interpretar la línea como renglón de compra
            parsed_item = self._parse_line_item(line)
            if parsed_item:
                detected_name, qty, unit_cost, line_total = parsed_item

                # Emparejamiento difuso con catálogo del tenant
                matched_id, matched_name, matched_sku, confidence = self._match_product(
                    detected_name, catalog_products
                )

                # Si no se encontró producto emparejado, incrementar contador de pendientes
                if not matched_id:
                    unmatched_count += 1

                # Construir DTO del renglón detectado
                item_dto = ReceiptOcrItemResponse(
                    raw_line=line,
                    detected_name=detected_name,
                    detected_quantity=qty,
                    detected_unit_cost_mxn=unit_cost,
                    detected_total_mxn=line_total,
                    matched_product_id=matched_id,
                    matched_product_name=matched_name,
                    matched_product_sku=matched_sku,
                    confidence_score=confidence,
                )
                parsed_items.append(item_dto)
                total_sum += line_total

        # Retornar respuesta consolidada
        return ReceiptOcrParseResponse(
            supplier_name=supplier_name,
            invoice_reference=invoice_reference,
            items=parsed_items,
            total_amount_mxn=total_sum.quantize(Decimal("0.01")),
            unmatched_items_count=unmatched_count,
        )

    async def _detect_supplier_name(
        self,
        lines: List[str],
        supplier_id: Optional[uuid.UUID],
        tenant_id: uuid.UUID,
    ) -> Optional[str]:
        """Detecta el nombre de la empresa proveedora."""
        if supplier_id:
            stmt = select(Supplier).where(Supplier.id == supplier_id, Supplier.tenant_id == tenant_id)
            res = await self.session.execute(stmt)
            supp = res.scalar_one_or_none()
            if supp:
                return supp.name

        known_suppliers = [
            "BIMBO", "MARINELA", "BARCEL", "TÍA ROSA", "FEMSA", "COCA-COLA", "COCA COLA",
            "PEPSICO", "SABRITAS", "GAMESA", "LALA", "ALPURA", "SIGMA", "FUD", "SAN RAFAEL",
            "CORONA", "MODELO", "HEINEKEN", "JUMEX", "DEL VALLE", "NESTLÉ", "NESTLE", "KELLOGG",
        ]

        for line in lines[:5]:
            upper_line = line.upper()
            for ks in known_suppliers:
                if ks in upper_line:
                    return ks.title()

        if lines:
            first_line = lines[0]
            if len(first_line) > 3 and not re.search(r"\d{2,}", first_line):
                return first_line

        return None

    def _detect_invoice_reference(self, lines: List[str]) -> Optional[str]:
        """Extrae el folio o número de remisión."""
        patterns = [
            r"(?:FACTURA|REMISION|REMISI[OÓ]N|FOLIO|NOTA|TICKET|DOC(?:UMENTO)?)\s*[:#.-]?\s*([A-Za-z0-9-]+)",
            r"(?:FAC|REM|NOT)\s*[:#.-]?\s*([A-Za-z0-9-]+)",
            r"#\s*([0-9]{4,})",
        ]
        for line in lines:
            for pat in patterns:
                m = re.search(pat, line, re.IGNORECASE)
                if m:
                    return m.group(1).strip()
        return None

    def _parse_line_item(self, line: str) -> Optional[Tuple[str, Decimal, Decimal, Decimal]]:
        """
        Interpreta una línea de texto de la factura extrayendo:
        (Nombre, Cantidad, Costo Unitario MXN, Total MXN).
        """
        # Ignorar líneas de cabecera o pie de ticket comunes
        ignore_keywords = [
            "SUBTOTAL", "TOTAL", "IVA", "IEPS", "RFC", "FECHA", "HORA", "PAGINA", "CLIENTE",
            "VENDEDOR", "DIRECCION", "TELEFONO", "GRACIAS", "CONDICIONES", "FIRMA",
        ]
        upper_line = line.upper()
        if any(kw in upper_line for kw in ignore_keywords) and not re.search(r"(?:PZ|CJA|KG|PAQ)", upper_line):
            if "SUBTOTAL" in upper_line or "TOTAL" in upper_line:
                return None

        # Patrón 1: [CANTIDAD] [UNIDAD opcional] [DESCRIPCIÓN] [PRECIO UNITARIO] [TOTAL]
        # Ej: "24 PZ Pan Blanco Grande $38.50 $924.00"
        p1 = re.match(
            r"^(\d+(?:\.\d+)?)\s*(?:PZ|PZA|PZAS|CJA|CJAS|KG|KGS|PAQ|PIEZAS)?\s+([A-Za-z0-9ÁÉÍÓÚáéíóúÑñ\s\-\.\/]+?)\s+\$?(\d+(?:\.\d{2})?)\s+\$?(\d+(?:\.\d{2})?)$",
            line.strip(),
            re.IGNORECASE,
        )
        if p1:
            qty = Decimal(p1.group(1))
            name = p1.group(2).strip()
            unit_cost = Decimal(p1.group(3))
            total = Decimal(p1.group(4))
            return name, qty, unit_cost, total

        # Patrón 2: [DESCRIPCIÓN] [CANTIDAD] [x | * | @ | por] [PRECIO] [= TOTAL opcional]
        # Ej: "Sabritas Sal 45g 30 x 12.50 = 375.00"
        p2 = re.match(
            r"^([A-Za-z0-9ÁÉÍÓÚáéíóúÑñ\s\-\.\/]+?)\s+(\d+(?:\.\d+)?)\s*(?:PZ|CJA|KG)?\s*(?:[xX*@]|por)\s*\$?(\d+(?:\.\d{2})?)\s*(?:=|\$)?\s*(\d+(?:\.\d{2})?)?$",
            line.strip(),
            re.IGNORECASE,
        )
        if p2:
            name = p2.group(1).strip()
            qty = Decimal(p2.group(2))
            unit_cost = Decimal(p2.group(3))
            if p2.group(4):
                total = Decimal(p2.group(4))
            else:
                total = (qty * unit_cost).quantize(Decimal("0.01"))
            return name, qty, unit_cost, total

        # Patrón 3: [CANTIDAD] [DESCRIPCIÓN] [TOTAL]
        # Ej: "10 Maruchan Pollo 150.00"
        p3 = re.match(
            r"^(\d+(?:\.\d+)?)\s+([A-Za-z0-9ÁÉÍÓÚáéíóúÑñ\s\-\.\/]+?)\s+\$?(\d+(?:\.\d{2})?)$",
            line.strip(),
            re.IGNORECASE,
        )
        if p3:
            qty = Decimal(p3.group(1))
            name = p3.group(2).strip()
            total = Decimal(p3.group(3))
            unit_cost = (total / qty).quantize(Decimal("0.01")) if qty > 0 else Decimal("0.00")
            return name, qty, unit_cost, total

        # Patrón 4: [DESCRIPCIÓN] [CANTIDAD] [PRECIO UNITARIO]
        # Ej: "Galletas Marias 20 15.50"
        p4 = re.match(
            r"^([A-Za-z0-9ÁÉÍÓÚáéíóúÑñ\s\-\.\/]+?)\s+(\d+(?:\.\d+)?)\s+\$?(\d+(?:\.\d{2})?)$",
            line.strip(),
            re.IGNORECASE,
        )
        if p4:
            name = p4.group(1).strip()
            qty = Decimal(p4.group(2))
            unit_cost = Decimal(p4.group(3))
            total = (qty * unit_cost).quantize(Decimal("0.01"))
            return name, qty, unit_cost, total

        return None

    async def _load_tenant_products(self, tenant_id: uuid.UUID) -> List[Product]:
        """Carga los productos activos del comercio para cotejo."""
        stmt = select(Product).where(Product.tenant_id == tenant_id, Product.is_active == True)
        res = await self.session.execute(stmt)
        return list(res.scalars().all())

    def _match_product(
        self,
        detected_name: str,
        catalog: List[Product],
    ) -> Tuple[Optional[uuid.UUID], Optional[str], Optional[str], float]:
        """
        Busca el producto más similar en el catálogo utilizando distancia de cadenas.
        Retorna (product_id, product_name, product_sku, confidence).
        """
        if not catalog:
            return None, None, None, 0.0

        best_prod: Optional[Product] = None
        best_ratio = 0.0
        normalized_detected = self._clean_text(detected_name)

        for prod in catalog:
            normalized_prod = self._clean_text(prod.name)
            # Similitud directa
            ratio = difflib.SequenceMatcher(None, normalized_detected, normalized_prod).ratio()
            
            # Bonificación si una cadena está contenida en la otra
            if normalized_detected in normalized_prod or normalized_prod in normalized_detected:
                ratio = max(ratio, 0.75)

            if ratio > best_ratio:
                best_ratio = ratio
                best_prod = prod

        # Umbral mínimo de coincidencia (55%)
        if best_ratio >= 0.55 and best_prod:
            return best_prod.id, best_prod.name, best_prod.sku, round(best_ratio, 2)

        return None, None, None, round(best_ratio, 2)

    def _clean_text(self, text: str) -> str:
        """Limpia caracteres especiales y pasa a minúsculas."""
        t = text.lower()
        t = re.sub(r"[^a-z0-9áéíóúñ\s]", "", t)
        return re.sub(r"\s+", " ", t).strip()
