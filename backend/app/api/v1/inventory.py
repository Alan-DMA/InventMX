from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, text
from decimal import Decimal
import csv
import io
from openpyxl import load_workbook
from typing import List, Dict, Any, Optional
from uuid import UUID

from app.core.database import get_db
from app.api.deps import get_current_user
from app.models.models import (
    User, Product, Category, Warehouse, Inventory, InventoryMovement, 
    Combo, ComboItem, Tenant
)
from app.schemas.inventory import (
    ProductCreate, ProductResponse, ProductUpdate, 
    CategoryCreate, CategoryResponse, ComboCreate, ComboResponse,
    ComboItemResponse,                                        # A-04: estaba faltando esta importación
    InventoryResponse, InventoryReserve, InventoryRelease,
    WarehouseResponse, InventoryAdjustRequest, InventoryTransferRequest, InventoryLoadRequest,
    InventoryMovementResponse,                                # A-07: para listar movimientos (Kardex)
)

router = APIRouter()

# Helper para obtener la tasa del inquilino actual
async def _get_tenant_exchange_rate(db: AsyncSession, tenant_id: Any) -> Decimal:
    result = await db.execute(select(Tenant.current_exchange_rate).where(Tenant.id == tenant_id))
    rate = result.scalar()
    return rate if rate is not None else Decimal("36.50")

# Helper para calcular el precio en VES de un producto
def _calculate_ves_price(price_usd: Decimal, price_ves_manual: Optional[Decimal], rate: Decimal) -> Decimal:
    if price_ves_manual is not None:
        return price_ves_manual
    return price_usd * rate


# --- Endpoints de Productos ---

@router.get("/products", response_model=List[ProductResponse])
async def list_products(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    skip: int = Query(default=0, ge=0, description="Número de registros a omitir (offset)"),
    limit: int = Query(default=50, ge=1, le=200, description="Máximo de registros a retornar (max 200)"),
    search: Optional[str] = Query(default=None, description="Buscar por nombre o código de barras"),
):
    """
    Lista los productos del Tenant con paginación y búsqueda opcional.
    Calcula dinámicamente el precio VES según la tasa del día del Tenant.
    """
    rate = await _get_tenant_exchange_rate(db, current_user.tenant_id)

    # M-12: Query paginada con filtro de búsqueda opcional
    query = select(Product).where(Product.is_active == True)
    if search:
        # Búsqueda por nombre o código de barras (case-insensitive)
        query = query.where(
            (Product.name.ilike(f"%{search}%")) | (Product.barcode.ilike(f"%{search}%"))
        )
    query = query.offset(skip).limit(limit)

    result = await db.execute(query)
    products = result.scalars().all()

    response = []
    for p in products:
        calculated_ves = _calculate_ves_price(p.price_usd, p.price_ves_manual, rate)
        
        # Mapeamos a ProductResponse incluyendo la columna calculada
        resp = ProductResponse(
            id=p.id,
            tenant_id=p.tenant_id,
            category_id=p.category_id,
            barcode=p.barcode,
            name=p.name,
            description=p.description,
            cost_usd=p.cost_usd,
            price_usd=p.price_usd,
            price_ves_manual=p.price_ves_manual,
            price_ves_calculated=calculated_ves,
            is_active=p.is_active,
            created_at=p.created_at,
            updated_at=p.updated_at
        )
        response.append(resp)
        
    return response


@router.post("/products", response_model=ProductResponse, status_code=status.HTTP_201_CREATED)
async def create_product(
    payload: ProductCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Crea un nuevo producto en el inventario e inicializa las existencias en el Almacén Principal.
    """
    # 1. Verificar duplicado de código de barras en el mismo tenant
    if payload.barcode:
        barcode_check = await db.execute(
            select(Product).where(Product.barcode == payload.barcode)
        )
        if barcode_check.scalars().first():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="El código de barras ya existe en este comercio."
            )

    # 2. Obtener o crear Almacén Principal por defecto
    wh_query = await db.execute(
        select(Warehouse).where(Warehouse.name == "Almacén Principal")
    )
    warehouse = wh_query.scalars().first()
    if not warehouse:
        warehouse = Warehouse(tenant_id=current_user.tenant_id, name="Almacén Principal", is_active=True)
        db.add(warehouse)
        await db.flush()

    # 3. Crear Producto
    new_product = Product(
        tenant_id=current_user.tenant_id,
        category_id=payload.category_id,
        barcode=payload.barcode,
        name=payload.name,
        description=payload.description,
        cost_usd=payload.cost_usd,
        price_usd=payload.price_usd,
        price_ves_manual=payload.price_ves_manual,
        is_active=True
    )
    db.add(new_product)
    await db.flush()

    # 4. Inicializar Stock en Almacén
    new_inventory = Inventory(
        tenant_id=current_user.tenant_id,
        product_id=new_product.id,
        warehouse_id=warehouse.id,
        stock_available=payload.stock_inicial,
        stock_reserved=Decimal("0.00")
    )
    db.add(new_inventory)

    # 5. Registrar Movimiento inicial (Kardex)
    if payload.stock_inicial > 0:
        movement = InventoryMovement(
            tenant_id=current_user.tenant_id,
            product_id=new_product.id,
            warehouse_id=warehouse.id,
            quantity=payload.stock_inicial,
            type="ENTRADA",
            notes="Carga inicial de producto nuevo"
        )
        db.add(movement)

    await db.commit()

    rate = await _get_tenant_exchange_rate(db, current_user.tenant_id)
    calculated_ves = _calculate_ves_price(new_product.price_usd, new_product.price_ves_manual, rate)

    return ProductResponse(
        id=new_product.id,
        tenant_id=new_product.tenant_id,
        category_id=new_product.category_id,
        barcode=new_product.barcode,
        name=new_product.name,
        description=new_product.description,
        cost_usd=new_product.cost_usd,
        price_usd=new_product.price_usd,
        price_ves_manual=new_product.price_ves_manual,
        price_ves_calculated=calculated_ves,
        is_active=new_product.is_active,
        created_at=new_product.created_at,
        updated_at=new_product.updated_at
    )


# --- Carga Masiva (Excel / CSV) ---

@router.post("/upload", status_code=status.HTTP_201_CREATED)
async def upload_inventory(
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Carga masiva de inventario a partir de un archivo Excel (.xlsx) o CSV.
    """
    content = await file.read()
    filename = file.filename.lower() if file.filename else ""
    
    rows: List[Dict[str, Any]] = []

    try:
        if filename.endswith(".csv"):
            # Leer CSV
            text_data = content.decode("utf-8")
            csv_reader = csv.reader(io.StringIO(text_data))
            header = next(csv_reader, None) # Leer cabecera
            # Formato esperado: nombre, codigo_barras, costo_usd, precio_usd, precio_ves_manual, stock_inicial
            for row in csv_reader:
                if not row or len(row) < 1:
                    continue
                rows.append({
                    "name": row[0].strip(),
                    "barcode": row[1].strip() if len(row) > 1 and row[1].strip() else None,
                    "cost_usd": Decimal(row[2].strip() or "0.00") if len(row) > 2 else Decimal("0.00"),
                    "price_usd": Decimal(row[3].strip() or "0.00") if len(row) > 3 else Decimal("0.00"),
                    "price_ves_manual": Decimal(row[4].strip() or "0.00") if len(row) > 4 and row[4].strip() else None,
                    "stock_inicial": Decimal(row[5].strip() or "0.00") if len(row) > 5 else Decimal("0.00"),
                })
        elif filename.endswith(".xlsx"):
            # Leer Excel usando openpyxl
            wb = load_workbook(io.BytesIO(content), data_only=True)
            sheet = wb.active
            # Recorrer filas omitiendo cabecera
            for r in list(sheet.iter_rows(values_only=True))[1:]:
                if not r or not r[0]:
                    continue
                rows.append({
                    "name": str(r[0]).strip(),
                    "barcode": str(r[1]).strip() if len(r) > 1 and r[1] is not None else None,
                    "cost_usd": Decimal(str(r[2] or "0.00")),
                    "price_usd": Decimal(str(r[3] or "0.00")),
                    "price_ves_manual": Decimal(str(r[4])) if len(r) > 4 and r[4] is not None else None,
                    "stock_inicial": Decimal(str(r[5] or "0.00")) if len(r) > 5 and r[5] is not None else Decimal("0.00"),
                })
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Formato de archivo no soportado. Debe ser .xlsx o .csv"
            )
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Error al analizar el archivo: {str(e)}"
        )

    # Buscar/crear almacén principal
    wh_query = await db.execute(select(Warehouse).where(Warehouse.name == "Almacén Principal"))
    warehouse = wh_query.scalars().first()
    if not warehouse:
        warehouse = Warehouse(tenant_id=current_user.tenant_id, name="Almacén Principal", is_active=True)
        db.add(warehouse)
        await db.flush()

    created_count = 0
    skipped_count = 0

    for r_data in rows:
        # Verificar si ya existe por código de barra en este tenant
        if r_data["barcode"]:
            dup_query = await db.execute(select(Product).where(Product.barcode == r_data["barcode"]))
            if dup_query.scalars().first():
                skipped_count += 1
                continue

        # Crear Producto
        new_prod = Product(
            tenant_id=current_user.tenant_id,
            barcode=r_data["barcode"],
            name=r_data["name"],
            cost_usd=r_data["cost_usd"],
            price_usd=r_data["price_usd"],
            price_ves_manual=r_data["price_ves_manual"],
            is_active=True
        )
        db.add(new_prod)
        await db.flush()

        # Inicializar Stock en Almacén
        new_inv = Inventory(
            tenant_id=current_user.tenant_id,
            product_id=new_prod.id,
            warehouse_id=warehouse.id,
            stock_available=r_data["stock_inicial"],
            stock_reserved=Decimal("0.00")
        )
        db.add(new_inv)

        # Kardex
        if r_data["stock_inicial"] > 0:
            mov = InventoryMovement(
                tenant_id=current_user.tenant_id,
                product_id=new_prod.id,
                warehouse_id=warehouse.id,
                quantity=r_data["stock_inicial"],
                type="ENTRADA",
                notes="Carga inicial masiva de inventario"
            )
            db.add(mov)
            
        created_count += 1

    await db.commit()
    return {"created": created_count, "skipped": skipped_count}


# --- Reserva y Liberación de Stock ---

@router.post("/reserve", response_model=InventoryResponse)
async def reserve_stock(
    payload: InventoryReserve,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Mueve cantidades de stock_available a stock_reserved.
    Lanza error si no hay suficientes existencias disponibles.
    """
    # Consultar registro de inventario
    inv_query = await db.execute(
        select(Inventory).where(
            (Inventory.product_id == payload.product_id) & 
            (Inventory.warehouse_id == payload.warehouse_id)
        )
    )
    inv = inv_query.scalars().first()
    if not inv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Inventario no encontrado para este producto y almacén."
        )

    # Validar disponibilidad
    if inv.stock_available < payload.quantity:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "INSUFFICIENT_STOCK",
                "message": f"No hay suficiente stock. Solicitado: {payload.quantity}, Disponible: {inv.stock_available}"
            }
        )

    # Mover stock
    inv.stock_available -= payload.quantity
    inv.stock_reserved += payload.quantity

    # Registrar movimiento
    movement = InventoryMovement(
        tenant_id=current_user.tenant_id,
        product_id=payload.product_id,
        warehouse_id=payload.warehouse_id,
        quantity=payload.quantity,
        type="RESERVA",
        reference_document=payload.sale_id,
        notes=f"Reserva para venta ID: {payload.sale_id}"
    )
    db.add(movement)
    await db.commit()
    return inv


@router.post("/release", response_model=InventoryResponse)
async def release_stock(
    payload: InventoryRelease,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Libera stock reservado devolviéndolo a disponible.
    """
    inv_query = await db.execute(
        select(Inventory).where(
            (Inventory.product_id == payload.product_id) & 
            (Inventory.warehouse_id == payload.warehouse_id)
        )
    )
    inv = inv_query.scalars().first()
    if not inv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Inventario no encontrado."
        )

    # M-05: Usar variable local en lugar de mutar el payload de Pydantic.
    # Si el stock reservado es menor a lo solicitado, liberamos solo lo que hay.
    qty_to_release = min(payload.quantity, inv.stock_reserved)

    # Mover stock de vuelta a disponible
    inv.stock_reserved -= qty_to_release
    inv.stock_available += qty_to_release

    # Registrar movimiento en Kardex
    movement = InventoryMovement(
        tenant_id=current_user.tenant_id,
        product_id=payload.product_id,
        warehouse_id=payload.warehouse_id,
        quantity=qty_to_release,
        type="LIBERACION",
        reference_document=payload.sale_id,
        notes=f"Liberación de reserva por anulación de venta ID: {payload.sale_id}"
    )
    db.add(movement)
    await db.commit()
    return inv


# --- Endpoints de Combos ---

@router.post("/combos", response_model=ComboResponse, status_code=status.HTTP_201_CREATED)
async def create_combo(
    payload: ComboCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Crea un nuevo Combo comercial con sus productos componentes.
    """
    # 1. Validar que todos los productos componentes existan y pertenezcan a este tenant
    for item in payload.items:
        prod_check = await db.execute(select(Product).where(Product.id == item.product_id))
        if not prod_check.scalars().first():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"El producto componente con ID {item.product_id} no existe."
            )

    # 2. Crear cabecera del Combo
    new_combo = Combo(
        tenant_id=current_user.tenant_id,
        name=payload.name,
        price_usd=payload.price_usd,
        is_active=True
    )
    db.add(new_combo)
    await db.flush()

    # 3. Vincular productos componentes
    for item in payload.items:
        combo_item = ComboItem(
            combo_id=new_combo.id,
            product_id=item.product_id,
            quantity=item.quantity
        )
        db.add(combo_item)
    
    await db.commit()
    
    # Consultar los items asociados de manera explícita para evitar lazy loading
    items_query = await db.execute(select(ComboItem).where(ComboItem.combo_id == new_combo.id))
    items_list = items_query.scalars().all()

    return ComboResponse(
        id=new_combo.id,
        tenant_id=new_combo.tenant_id,
        name=new_combo.name,
        price_usd=new_combo.price_usd,
        is_active=new_combo.is_active,
        created_at=new_combo.created_at,
        items=[ComboItemResponse(product_id=i.product_id, quantity=i.quantity) for i in items_list]
    )


# --- Actualización de Productos ---
@router.put("/products/{product_id}", response_model=ProductResponse)
async def update_product(
    product_id: UUID,
    payload: ProductUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    prod_query = await db.execute(select(Product).where(Product.id == product_id))
    product = prod_query.scalars().first()
    if not product:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")

    if payload.name is not None:
        product.name = payload.name
    if payload.barcode is not None:
        product.barcode = payload.barcode
    if payload.category_id is not None:
        product.category_id = payload.category_id
    if payload.description is not None:
        product.description = payload.description
    if payload.cost_usd is not None:
        product.cost_usd = payload.cost_usd
    if payload.price_usd is not None:
        product.price_usd = payload.price_usd
    if payload.price_ves_manual is not None:
        product.price_ves_manual = payload.price_ves_manual
    if payload.is_active is not None:
        product.is_active = payload.is_active

    await db.commit()
    await db.refresh(product)

    rate = await _get_tenant_exchange_rate(db, current_user.tenant_id)
    calculated_ves = _calculate_ves_price(product.price_usd, product.price_ves_manual, rate)

    return ProductResponse(
        id=product.id,
        tenant_id=product.tenant_id,
        category_id=product.category_id,
        barcode=product.barcode,
        name=product.name,
        description=product.description,
        cost_usd=product.cost_usd,
        price_usd=product.price_usd,
        price_ves_manual=product.price_ves_manual,
        price_ves_calculated=calculated_ves,
        is_active=product.is_active,
        created_at=product.created_at,
        updated_at=product.updated_at
    )


# --- Almacenes ---
@router.get("/warehouses", response_model=List[WarehouseResponse])
async def list_warehouses(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    result = await db.execute(select(Warehouse).where(Warehouse.is_active == True))
    warehouses = result.scalars().all()
    if not warehouses:
        wh = Warehouse(tenant_id=current_user.tenant_id, name="Almacén Principal", is_active=True)
        db.add(wh)
        await db.commit()
        await db.refresh(wh)
        return [wh]
    return warehouses


# --- Operaciones de Inventario ---
@router.post("/adjust")
async def adjust_stock(
    payload: InventoryAdjustRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if payload.warehouse_id:
        wh_res = await db.execute(select(Warehouse).where(Warehouse.id == payload.warehouse_id))
        warehouse = wh_res.scalars().first()
    else:
        wh_res = await db.execute(select(Warehouse).where(Warehouse.name == "Almacén Principal"))
        warehouse = wh_res.scalars().first()
        if not warehouse:
            wh_res = await db.execute(select(Warehouse).where(Warehouse.is_active == True))
            warehouse = wh_res.scalars().first()

    if not warehouse:
        raise HTTPException(status_code=404, detail="Almacén no encontrado")

    inv_res = await db.execute(
        select(Inventory).where(
            Inventory.product_id == payload.product_id,
            Inventory.warehouse_id == warehouse.id
        )
    )
    inventory = inv_res.scalars().first()
    if not inventory:
        inventory = Inventory(
            tenant_id=current_user.tenant_id,
            product_id=payload.product_id,
            warehouse_id=warehouse.id,
            stock_available=Decimal("0.00"),
            stock_reserved=Decimal("0.00")
        )
        db.add(inventory)

    inventory.stock_available += payload.quantity_change
    if inventory.stock_available < 0:
        inventory.stock_available = Decimal("0.00")

    movement = InventoryMovement(
        tenant_id=current_user.tenant_id,
        product_id=payload.product_id,
        warehouse_id=warehouse.id,
        quantity=abs(payload.quantity_change),
        type="ENTRADA" if payload.quantity_change >= 0 else "SALIDA",
        notes=payload.reason
    )
    db.add(movement)
    await db.commit()
    return {"message": "Ajuste aplicado exitosamente", "stock_available": inventory.stock_available}


@router.post("/transfer")
async def transfer_stock(
    payload: InventoryTransferRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if payload.origin_warehouse_id == payload.target_warehouse_id:
        raise HTTPException(status_code=400, detail="El almacén de origen y destino deben ser diferentes")

    orig_res = await db.execute(
        select(Inventory).where(
            Inventory.product_id == payload.product_id,
            Inventory.warehouse_id == payload.origin_warehouse_id
        )
    )
    orig_inv = orig_res.scalars().first()
    if not orig_inv or orig_inv.stock_available < payload.quantity:
        raise HTTPException(status_code=400, detail="Existencias insuficientes en el almacén de origen")

    dest_res = await db.execute(
        select(Inventory).where(
            Inventory.product_id == payload.product_id,
            Inventory.warehouse_id == payload.target_warehouse_id
        )
    )
    dest_inv = dest_res.scalars().first()
    if not dest_inv:
        dest_inv = Inventory(
            tenant_id=current_user.tenant_id,
            product_id=payload.product_id,
            warehouse_id=payload.target_warehouse_id,
            stock_available=Decimal("0.00"),
            stock_reserved=Decimal("0.00")
        )
        db.add(dest_inv)

    orig_inv.stock_available -= payload.quantity
    dest_inv.stock_available += payload.quantity

    mov_out = InventoryMovement(
        tenant_id=current_user.tenant_id,
        product_id=payload.product_id,
        warehouse_id=payload.origin_warehouse_id,
        quantity=payload.quantity,
        type="SALIDA",
        notes=f"Traslado hacia almacén {payload.target_warehouse_id}: {payload.notes or ''}"
    )
    mov_in = InventoryMovement(
        tenant_id=current_user.tenant_id,
        product_id=payload.product_id,
        warehouse_id=payload.target_warehouse_id,
        quantity=payload.quantity,
        type="ENTRADA",
        notes=f"Traslado desde almacén {payload.origin_warehouse_id}: {payload.notes or ''}"
    )
    db.add_all([mov_out, mov_in])
    await db.commit()
    return {"message": "Traslado completado exitosamente"}


@router.post("/load")
async def load_inventory(
    payload: InventoryLoadRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    if payload.warehouse_id:
        wh_res = await db.execute(select(Warehouse).where(Warehouse.id == payload.warehouse_id))
        warehouse = wh_res.scalars().first()
    else:
        wh_res = await db.execute(select(Warehouse).where(Warehouse.is_active == True))
        warehouse = wh_res.scalars().first()

    if not warehouse:
        raise HTTPException(status_code=404, detail="Almacén no encontrado")

    for item in payload.items:
        inv_res = await db.execute(
            select(Inventory).where(
                Inventory.product_id == item.product_id,
                Inventory.warehouse_id == warehouse.id
            )
        )
        inventory = inv_res.scalars().first()
        if not inventory:
            inventory = Inventory(
                tenant_id=current_user.tenant_id,
                product_id=item.product_id,
                warehouse_id=warehouse.id,
                stock_available=Decimal("0.00"),
                stock_reserved=Decimal("0.00")
            )
            db.add(inventory)

        inventory.stock_available += item.quantity

        movement = InventoryMovement(
            tenant_id=current_user.tenant_id,
            product_id=item.product_id,
            warehouse_id=warehouse.id,
            quantity=item.quantity,
            type="ENTRADA",
            notes=f"Carga por {payload.document_type} {payload.document_number or ''} - Proveedor: {payload.supplier_name or 'N/A'}"
        )
        db.add(movement)

    await db.commit()
    return {"message": f"Carga de {len(payload.items)} productos completada exitosamente"}


# ─────────────────────────────────────────────────────────
# A-07: GET /inventory/movements — Kardex de movimientos
# ─────────────────────────────────────────────────────────

@router.get("/movements", response_model=List[InventoryMovementResponse])
async def list_inventory_movements(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
    product_id: Optional[UUID] = Query(default=None, description="Filtrar por producto"),
    warehouse_id: Optional[UUID] = Query(default=None, description="Filtrar por almacén"),
    movement_type: Optional[str] = Query(default=None, alias="type", description="Filtrar por tipo: ENTRADA, SALIDA, RESERVA, LIBERACION, AJUSTE, DEVOLUCION, TRASLADO"),
    skip: int = Query(default=0, ge=0, description="Offset de paginación"),
    limit: int = Query(default=100, ge=1, le=500, description="Límite de resultados (máx 500)"),
):
    """
    Retorna el Kardex de movimientos de inventario del Tenant actual.
    Soporta filtros por producto, almacén y tipo de movimiento, con paginación.
    Ordenado por fecha descendente (más reciente primero).
    """
    # Construir query con filtros opcionales
    query = select(InventoryMovement)
    if product_id:
        query = query.where(InventoryMovement.product_id == product_id)
    if warehouse_id:
        query = query.where(InventoryMovement.warehouse_id == warehouse_id)
    if movement_type:
        query = query.where(InventoryMovement.type == movement_type.upper())

    # Ordenar por más reciente primero y paginar
    query = query.order_by(InventoryMovement.created_at.desc()).offset(skip).limit(limit)

    result = await db.execute(query)
    movements = result.scalars().all()
    return movements


@router.get("/products/{product_id}/inventory", response_model=List[InventoryResponse])
async def get_product_inventory(
    product_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retorna el estado actual de stock de un producto en todos los almacenes del Tenant.
    Útil para saber cuánto hay disponible vs reservado por almacén.
    """
    # Verificar que el producto existe y pertenece al tenant (RLS lo protege)
    prod_res = await db.execute(select(Product).where(Product.id == product_id))
    product = prod_res.scalars().first()
    if not product:
        raise HTTPException(status_code=404, detail="Producto no encontrado.")

    # Buscar todos los registros de inventario del producto
    inv_res = await db.execute(
        select(Inventory).where(Inventory.product_id == product_id)
    )
    inventory_records = inv_res.scalars().all()
    return inventory_records
