import asyncio
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from sqlalchemy import select, text
from app.core.database.session import AsyncSessionLocal
from app.modules.inventory.domain.inventory_movement import InventoryMovement, MovementType
from app.modules.inventory.domain.product_stock import ProductStock
from app.modules.inventory.domain.warehouse import Warehouse
from app.modules.sales_pos.domain.sale import Sale, SaleItem, SaleStatus


async def release_expired_reservations_loop():
    """
    Tarea periódica que corre indefinidamente en segundo plano.
    Busca ventas en PENDING_PAYMENT de más de 15 minutos y libera su stock.
    Bypassea RLS limpiando el tenant_id del contexto para actuar sobre todos los tenants.
    """
    print("Iniciando servicio de liberación de stock reservado (TTL 15 min)...")
    while True:
        try:
            # Esperar 60 segundos entre ejecuciones
            await asyncio.sleep(60)

            async with AsyncSessionLocal() as session:
                # 1. Desactivar RLS temporalmente en la sesión para poder ver todas las ventas de todos los tenants
                await session.execute(text("SELECT set_config('app.current_tenant', '', false)"))

                # 2. Consultar ventas expiradas
                time_threshold = datetime.now(timezone.utc) - timedelta(minutes=15)

                sales_query = select(Sale).where(
                    (Sale.status == SaleStatus.PENDING_PAYMENT) &
                    (Sale.created_at <= time_threshold)
                )
                sales_result = await session.execute(sales_query)
                expired_sales = sales_result.scalars().all()

                if not expired_sales:
                    continue

                print(f"Detectadas {len(expired_sales)} ventas expiradas para liberar stock.")

                for sale in expired_sales:
                    # Cargar los items de la venta
                    items_query = select(SaleItem).where(SaleItem.sale_id == sale.id)
                    items_result = await session.execute(items_query)
                    items = items_result.scalars().all()

                    # Obtener el almacén principal de este tenant
                    wh_query = select(Warehouse).where(
                        (Warehouse.tenant_id == sale.tenant_id) &
                        (Warehouse.name == "Almacén Principal")
                    )
                    wh_result = await session.execute(wh_query)
                    warehouse = wh_result.scalars().first()

                    if not warehouse:
                        # Si no hay almacén principal, marcamos como cancelada y continuamos
                        sale.status = SaleStatus.CANCELLED
                        sale.updated_at = datetime.now(timezone.utc)
                        continue

                    for item in items:
                        # Obtener registro de inventario para este producto
                        inv_query = select(ProductStock).where(
                            (ProductStock.product_id == item.product_id) &
                            (ProductStock.warehouse_id == warehouse.id)
                        )
                        inv_result = await session.execute(inv_query)
                        stock = inv_result.scalars().first()

                        if stock:
                            # Liberar únicamente lo que esté reservado por seguridad
                            qty_to_release = min(item.quantity, stock.reserved_stock)

                            stock.reserved_stock = max(Decimal("0.00"), stock.reserved_stock - qty_to_release)

                            # Registrar movimiento en Kardex
                            movement = InventoryMovement(
                                tenant_id=sale.tenant_id,
                                product_id=item.product_id,
                                warehouse_id=warehouse.id,
                                quantity=-qty_to_release,
                                movement_type=MovementType.RESERVATION_RELEASE,
                                previous_stock=stock.current_stock,
                                new_stock=stock.current_stock,
                                unit_cost_mxn=Decimal("0.00"),
                                reference_id=sale.id,
                                notes="Expiración automática por TTL de 15 minutos (Venta anulada)"
                            )
                            session.add(movement)

                    # Anular cabecera de la venta
                    sale.status = SaleStatus.CANCELLED
                    sale.updated_at = datetime.now(timezone.utc)
                    print(f"Venta {sale.id} (Tenant {sale.tenant_id}) cancelada y stock devuelto a disponible.")

                await session.commit()

        except asyncio.CancelledError:
            print("Servicio de liberación de stock reservado detenido.")
            break
        except Exception as e:
            print(f"Error en el ciclo de limpieza de stock: {e}")
            # Continuar el loop a pesar del error
