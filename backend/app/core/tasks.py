import asyncio
from datetime import datetime, timedelta, timezone
from sqlalchemy import select, text
from app.core.database import AsyncSessionLocal
from app.models.models import Sale, SaleItem, Inventory, InventoryMovement, Warehouse

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
                # Usamos naive UTC datetime porque en Postgres la columna created_at es TIMESTAMP WITHOUT TIME ZONE
                time_threshold = (datetime.now(timezone.utc) - timedelta(minutes=15)).replace(tzinfo=None)
                
                sales_query = select(Sale).where(
                    (Sale.status == "PENDING_PAYMENT") & 
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
                        sale.status = "CANCELLED"
                        sale.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
                        continue
                    
                    for item in items:
                        # Obtener registro de inventario para este producto
                        inv_query = select(Inventory).where(
                            (Inventory.product_id == item.product_id) & 
                            (Inventory.warehouse_id == warehouse.id)
                        )
                        inv_result = await session.execute(inv_query)
                        inv = inv_result.scalars().first()
                        
                        if inv:
                            # Liberar únicamente lo que esté reservado por seguridad
                            qty_to_release = min(item.quantity, inv.stock_reserved)
                            
                            inv.stock_reserved -= qty_to_release
                            inv.stock_available += qty_to_release
                            
                            # Registrar movimiento en Kardex
                            movement = InventoryMovement(
                                tenant_id=sale.tenant_id,
                                product_id=item.product_id,
                                warehouse_id=warehouse.id,
                                quantity=qty_to_release,
                                type="LIBERACION",
                                reference_document=str(sale.id),
                                notes=f"Expiración automática por TTL de 15 minutos (Venta anulada)"
                            )
                            session.add(movement)
                    
                    # Anular cabecera de la venta
                    sale.status = "CANCELLED"
                    sale.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
                    print(f"Venta {sale.id} (Tenant {sale.tenant_id}) cancelada y stock devuelto a disponible.")
                
                await session.commit()
                
        except asyncio.CancelledError:
            print("Servicio de liberación de stock reservado detenido.")
            break
        except Exception as e:
            print(f"Error en el ciclo de limpieza de stock: {e}")
            # Continuar el loop a pesar del error
