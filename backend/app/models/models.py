import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Numeric, Boolean, DateTime, ForeignKey, UniqueConstraint, Index, Table, Text, text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import relationship
from app.core.database import Base

# Tabla de relación muchos a muchos: Roles <-> Permisos
role_permissions = Table(
    'role_permissions',
    Base.metadata,
    Column('role_id', UUID(as_uuid=True), ForeignKey('roles.id', ondelete='CASCADE'), primary_key=True),
    Column('permission_id', UUID(as_uuid=True), ForeignKey('permissions.id', ondelete='CASCADE'), primary_key=True)
)

class Plan(Base):
    __tablename__ = 'plans'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    name = Column(String(100), nullable=False)
    price = Column(Numeric(10, 2), nullable=False)
    max_users = Column(Integer, nullable=False)
    max_warehouses = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenants = relationship("Tenant", back_populates="plan")
    subscription_invoices = relationship("SubscriptionInvoice", back_populates="plan")


class Tenant(Base):
    __tablename__ = 'tenants'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    name = Column(String(255), nullable=False)
    preferred_payment_method = Column(String(50))
    payment_instructions = Column(Text)
    code = Column(String(20), unique=True, nullable=False)

    plan_id = Column(UUID(as_uuid=True), ForeignKey('plans.id', ondelete='SET NULL'))
    current_exchange_rate = Column(Numeric(12, 4), nullable=False, default=36.50, server_default=text("36.50"))
    subscription_status = Column(String(50), nullable=False, default='ACTIVE', server_default=text("'ACTIVE'"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    plan = relationship("Plan", back_populates="tenants")
    roles = relationship("Role", back_populates="tenant", cascade="all, delete-orphan")
    users = relationship("User", back_populates="tenant", cascade="all, delete-orphan")
    categories = relationship("Category", back_populates="tenant", cascade="all, delete-orphan")
    products = relationship("Product", back_populates="tenant", cascade="all, delete-orphan")
    warehouses = relationship("Warehouse", back_populates="tenant", cascade="all, delete-orphan")
    inventory = relationship("Inventory", back_populates="tenant", cascade="all, delete-orphan")
    inventory_movements = relationship("InventoryMovement", back_populates="tenant", cascade="all, delete-orphan")
    combos = relationship("Combo", back_populates="tenant", cascade="all, delete-orphan")
    sales = relationship("Sale", back_populates="tenant", cascade="all, delete-orphan")
    sale_items = relationship("SaleItem", back_populates="tenant", cascade="all, delete-orphan")
    sale_payments = relationship("SalePayment", back_populates="tenant", cascade="all, delete-orphan")
    suppliers = relationship("Supplier", back_populates="tenant", cascade="all, delete-orphan")
    purchase_orders = relationship("PurchaseOrder", back_populates="tenant", cascade="all, delete-orphan")
    purchase_items = relationship("PurchaseItem", back_populates="tenant", cascade="all, delete-orphan")
    accounts_payable = relationship("AccountsPayable", back_populates="tenant", cascade="all, delete-orphan")
    cash_registers = relationship("CashRegister", back_populates="tenant", cascade="all, delete-orphan")
    cash_sessions = relationship("CashSession", back_populates="tenant", cascade="all, delete-orphan")
    cash_movements = relationship("CashMovement", back_populates="tenant", cascade="all, delete-orphan")
    subscription_invoices = relationship("SubscriptionInvoice", back_populates="tenant", cascade="all, delete-orphan")
    payment_validations = relationship("SubscriptionPaymentValidation", back_populates="tenant", cascade="all, delete-orphan")
    catalog_page = relationship("CatalogPage", uselist=False, back_populates="tenant", cascade="all, delete-orphan")
    catalog_orders = relationship("CatalogOrder", back_populates="tenant", cascade="all, delete-orphan")
    audit_logs = relationship("AuditLog", back_populates="tenant", cascade="all, delete-orphan")


class Role(Base):
    __tablename__ = 'roles'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_roles_tenant_name'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(100), nullable=False)
    description = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="roles")
    users = relationship("User", back_populates="role")
    permissions = relationship("Permission", secondary=role_permissions, back_populates="roles")


class Permission(Base):
    __tablename__ = 'permissions'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    name = Column(String(100), unique=True, nullable=False)
    description = Column(String)

    # Relaciones
    roles = relationship("Role", secondary=role_permissions, back_populates="permissions")


class User(Base):
    __tablename__ = 'users'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'email', name='uq_users_tenant_email'),
        UniqueConstraint('tenant_id', 'username', name='uq_users_tenant_username'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    username = Column(String(100), nullable=False)
    email = Column(String(255), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role_id = Column(UUID(as_uuid=True), ForeignKey('roles.id', ondelete='SET NULL'))
    commission_rate = Column(Numeric(5, 2), nullable=False, default=0.00, server_default=text("0"))
    is_active = Column(Boolean, default=True, server_default=text("true"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="users")
    role = relationship("Role", back_populates="users")
    cash_sessions = relationship("CashSession", back_populates="user")
    validated_payments = relationship("SubscriptionPaymentValidation", back_populates="validator")


class Category(Base):
    __tablename__ = 'categories'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_categories_tenant_name'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(100), nullable=False)
    description = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="categories")
    products = relationship("Product", back_populates="category")


class Product(Base):
    __tablename__ = 'products'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'barcode', name='uq_products_tenant_barcode'),
        Index('idx_products_tenant_name', 'tenant_id', 'name'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    category_id = Column(UUID(as_uuid=True), ForeignKey('categories.id', ondelete='SET NULL'))
    barcode = Column(String(100))
    name = Column(String(255), nullable=False)
    description = Column(String)
    cost_usd = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    price_usd = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    price_ves_manual = Column(Numeric(12, 4))
    is_active = Column(Boolean, default=True, server_default=text("true"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="products")
    category = relationship("Category", back_populates="products")
    inventory = relationship("Inventory", back_populates="product", cascade="all, delete-orphan")


class Warehouse(Base):
    __tablename__ = 'warehouses'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'name', name='uq_warehouses_tenant_name'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(100), nullable=False)
    is_active = Column(Boolean, default=True, server_default=text("true"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="warehouses")
    inventory = relationship("Inventory", back_populates="warehouse", cascade="all, delete-orphan")


class Inventory(Base):
    __tablename__ = 'inventory'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'product_id', 'warehouse_id', name='uq_inventory_tenant_product_warehouse'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey('products.id', ondelete='CASCADE'), nullable=False)
    warehouse_id = Column(UUID(as_uuid=True), ForeignKey('warehouses.id', ondelete='CASCADE'), nullable=False)
    stock_available = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    stock_reserved = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="inventory")
    product = relationship("Product", back_populates="inventory")
    warehouse = relationship("Warehouse", back_populates="inventory")


class InventoryMovement(Base):
    __tablename__ = 'inventory_movements'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey('products.id', ondelete='CASCADE'), nullable=False)
    warehouse_id = Column(UUID(as_uuid=True), ForeignKey('warehouses.id', ondelete='CASCADE'), nullable=False)
    quantity = Column(Numeric(12, 4), nullable=False)
    type = Column(String(50), nullable=False)  # ENTRADA, SALIDA, TRASLADO, AJUSTE, RESERVA, LIBERACION
    reference_document = Column(String(100))
    notes = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="inventory_movements")
    # A-02: Relaciones con Product y Warehouse para poder acceder a .product.name y .warehouse.name
    product = relationship("Product")    # Unidireccional (sin back_populates)
    warehouse = relationship("Warehouse") # Unidireccional (sin back_populates)


class Combo(Base):
    __tablename__ = 'combos'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(255), nullable=False)
    price_usd = Column(Numeric(12, 4), nullable=False)
    is_active = Column(Boolean, default=True, server_default=text("true"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="combos")
    items = relationship("ComboItem", back_populates="combo", cascade="all, delete-orphan")


class ComboItem(Base):
    __tablename__ = 'combo_items'

    combo_id = Column(UUID(as_uuid=True), ForeignKey('combos.id', ondelete='CASCADE'), primary_key=True)
    product_id = Column(UUID(as_uuid=True), ForeignKey('products.id', ondelete='CASCADE'), primary_key=True)
    quantity = Column(Numeric(12, 4), nullable=False)

    # Relaciones
    combo = relationship("Combo", back_populates="items")
    product = relationship("Product")  # M-03: Acceso directo a nombre/precio del componente


class Sale(Base):
    __tablename__ = 'sales'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    exchange_rate_applied = Column(Numeric(12, 4), nullable=False)
    status = Column(String(50), nullable=False, default='DRAFT', server_default=text("'DRAFT'"))
    total_usd = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    seller_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    commission_amount_usd = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="sales")
    items = relationship("SaleItem", back_populates="sale", cascade="all, delete-orphan")
    payments = relationship("SalePayment", back_populates="sale", cascade="all, delete-orphan")
    seller = relationship("User", foreign_keys="Sale.seller_id")          # Vendedor con comisión
    user   = relationship("User", foreign_keys="Sale.user_id")            # M-15: Cajero que abrió la venta


class SaleItem(Base):
    __tablename__ = 'sale_items'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    sale_id = Column(UUID(as_uuid=True), ForeignKey('sales.id', ondelete='CASCADE'), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey('products.id', ondelete='SET NULL'))
    quantity = Column(Numeric(12, 4), nullable=False)
    unit_cost_usd = Column(Numeric(12, 4), nullable=False)
    unit_price_usd = Column(Numeric(12, 4), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="sale_items")
    sale = relationship("Sale", back_populates="items")


class SalePayment(Base):
    __tablename__ = 'sale_payments'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    sale_id = Column(UUID(as_uuid=True), ForeignKey('sales.id', ondelete='CASCADE'), nullable=False)
    payment_method = Column(String(50), nullable=False)  # EFECTIVO_USD, EFECTIVO_VES, PAGO_MOVIL, ZELLE, TARJETA
    amount_usd = Column(Numeric(12, 4), nullable=False)
    amount_ves = Column(Numeric(12, 4), nullable=False)
    reference_number = Column(String(100))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="sale_payments")
    sale = relationship("Sale", back_populates="payments")


class Supplier(Base):
    __tablename__ = 'suppliers'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'rif', name='uq_suppliers_tenant_rif'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(255), nullable=False)
    contact_name = Column(String(255))
    phone = Column(String(50))
    email = Column(String(255))
    rif = Column(String(50))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="suppliers")


class PurchaseOrder(Base):
    __tablename__ = 'purchase_orders'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    supplier_id = Column(UUID(as_uuid=True), ForeignKey('suppliers.id', ondelete='CASCADE'), nullable=False)
    status = Column(String(50), nullable=False, default='PENDIENTE', server_default=text("'PENDIENTE'"))
    invoice_file_url = Column(String(255))
    total_usd = Column(Numeric(12, 4), nullable=False, default=0.0, server_default=text("0"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="purchase_orders")


class PurchaseItem(Base):
    __tablename__ = 'purchase_items'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    purchase_order_id = Column(UUID(as_uuid=True), ForeignKey('purchase_orders.id', ondelete='CASCADE'), nullable=False)
    product_id = Column(UUID(as_uuid=True), ForeignKey('products.id', ondelete='CASCADE'), nullable=False)
    quantity = Column(Numeric(12, 4), nullable=False)
    unit_cost_usd = Column(Numeric(12, 4), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="purchase_items")


class AccountsPayable(Base):
    __tablename__ = 'accounts_payable'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    supplier_id = Column(UUID(as_uuid=True), ForeignKey('suppliers.id', ondelete='CASCADE'), nullable=False)
    purchase_order_id = Column(UUID(as_uuid=True), ForeignKey('purchase_orders.id', ondelete='SET NULL'))
    amount_usd = Column(Numeric(12, 4), nullable=False)
    amount_ves = Column(Numeric(12, 4), nullable=False)
    due_date = Column(DateTime, nullable=False)
    status = Column(String(50), nullable=False, default='PENDIENTE', server_default=text("'PENDIENTE'"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="accounts_payable")


class CashRegister(Base):
    __tablename__ = 'cash_registers'
    __table_args__ = (
        UniqueConstraint('tenant_id', 'warehouse_id', 'name', name='uq_cash_registers_tenant_warehouse_name'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    warehouse_id = Column(UUID(as_uuid=True), ForeignKey('warehouses.id', ondelete='CASCADE'), nullable=False)
    name = Column(String(100), nullable=False)
    is_active = Column(Boolean, default=True, server_default=text("true"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="cash_registers")


class CashSession(Base):
    __tablename__ = 'cash_sessions'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    cash_register_id = Column(UUID(as_uuid=True), ForeignKey('cash_registers.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    opened_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    closed_at = Column(DateTime)
    initial_balance_usd = Column(Numeric(12, 4), nullable=False)
    initial_balance_ves = Column(Numeric(12, 4), nullable=False)
    expected_balance_usd = Column(Numeric(12, 4))
    expected_balance_ves = Column(Numeric(12, 4))
    real_balance_usd = Column(Numeric(12, 4))
    real_balance_ves = Column(Numeric(12, 4))
    status = Column(String(50), nullable=False, default='ABIERTA', server_default=text("'ABIERTA'"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="cash_sessions")
    user = relationship("User", back_populates="cash_sessions")


class CashMovement(Base):
    __tablename__ = 'cash_movements'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    cash_session_id = Column(UUID(as_uuid=True), ForeignKey('cash_sessions.id', ondelete='CASCADE'), nullable=False)
    amount_usd = Column(Numeric(12, 4), nullable=False)
    amount_ves = Column(Numeric(12, 4), nullable=False)
    type = Column(String(50), nullable=False)  # VENTA, RETIRO, DEPOSITO, AJUSTE
    reference_id = Column(String(100))
    notes = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="cash_movements")


class SubscriptionInvoice(Base):
    __tablename__ = 'subscription_invoices'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    plan_id = Column(UUID(as_uuid=True), ForeignKey('plans.id', ondelete='CASCADE'), nullable=False)
    amount = Column(Numeric(10, 2), nullable=False)
    due_date = Column(DateTime, nullable=False)
    status = Column(String(50), nullable=False, default='PENDIENTE', server_default=text("'PENDIENTE'"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="subscription_invoices")
    plan = relationship("Plan", back_populates="subscription_invoices")


class BinancePaymentProcessed(Base):
    __tablename__ = 'binance_payments_processed'

    binance_transaction_id = Column(String(255), primary_key=True)
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    subscription_invoice_id = Column(UUID(as_uuid=True), ForeignKey('subscription_invoices.id', ondelete='CASCADE'), nullable=False)
    amount = Column(Numeric(10, 2), nullable=False)
    processed_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))


class SubscriptionPaymentValidation(Base):
    __tablename__ = 'subscription_payment_validations'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    subscription_invoice_id = Column(UUID(as_uuid=True), ForeignKey('subscription_invoices.id', ondelete='CASCADE'), nullable=False)
    payment_method = Column(String(50), nullable=False)  # PAGO_MOVIL, ZINLI, PAYPAL, EFECTIVO
    reference_number = Column(String(100))
    receipt_file_url = Column(String(255))
    status = Column(String(50), nullable=False, default='PENDIENTE', server_default=text("'PENDIENTE'"))
    validated_by = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='SET NULL'))
    validation_notes = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="payment_validations")
    validator = relationship("User", back_populates="validated_payments")


class CatalogPage(Base):
    __tablename__ = 'catalog_pages'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False, unique=True)
    slug = Column(String(100), nullable=False, unique=True)
    title = Column(String(255), nullable=False)
    description = Column(String)
    whatsapp_number = Column(String(50), nullable=False)
    is_active = Column(Boolean, default=True, server_default=text("true"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="catalog_page")


class CatalogOrder(Base):
    __tablename__ = 'catalog_orders'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    customer_name = Column(String(255), nullable=False)
    customer_phone = Column(String(50), nullable=False)
    total_usd = Column(Numeric(12, 4), nullable=False)
    status = Column(String(50), nullable=False, default='ENVIADO', server_default=text("'ENVIADO'"))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="catalog_orders")


class AuditLog(Base):
    __tablename__ = 'audit_logs'

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4, server_default=text("gen_random_uuid()"))
    tenant_id = Column(UUID(as_uuid=True), ForeignKey('tenants.id', ondelete='CASCADE'), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey('users.id', ondelete='CASCADE'), nullable=False)
    action = Column(String(100), nullable=False)  # e.g. 'PRODUCT_PRICE_CHANGED'
    entity_type = Column(String(100), nullable=False)  # e.g. 'products'
    entity_id = Column(UUID(as_uuid=True), nullable=False)
    old_values = Column(JSONB)
    new_values = Column(JSONB)
    ip_address = Column(String(45))
    created_at = Column(DateTime, default=datetime.utcnow, server_default=text("now()"))

    # Relaciones
    tenant = relationship("Tenant", back_populates="audit_logs")
