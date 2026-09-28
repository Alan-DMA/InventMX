"""
Panel de administración de la plataforma (fundadores y soporte).

Scope de **plataforma**, no de comercio: sus operadores no pertenecen a ningún
tenant y sus tokens se firman con otra llave. Por decisión de Eduardo (P2, Sep
2026) sólo ve **metadatos** de los comercios; este módulo no importa dominios de
contenido (inventario, ventas, clientes, compras, caja, analítica) y un test lo
vigila.
"""
