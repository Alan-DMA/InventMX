from typing import Any, Optional


class AppException(Exception):
    """Excepción base del sistema con código de error y detalle HTTP."""

    def __init__(
        self,
        message: str,
        code: str = "INTERNAL_SERVER_ERROR",
        status_code: int = 500,
        details: Optional[Any] = None,
    ):
        super().__init__(message)
        self.message = message
        self.code = code
        self.status_code = status_code
        self.details = details


class UnauthorizedException(AppException):
    def __init__(self, message: str = "Credenciales inválidas o token no proporcionado", details: Optional[Any] = None):
        super().__init__(
            message=message,
            code="AUTH_UNAUTHORIZED",
            status_code=401,
            details=details,
        )


class ForbiddenException(AppException):
    def __init__(self, message: str = "No tienes permisos suficientes para realizar esta acción", details: Optional[Any] = None):
        super().__init__(
            message=message,
            code="AUTH_FORBIDDEN",
            status_code=403,
            details=details,
        )


class NotFoundException(AppException):
    def __init__(self, message: str = "El recurso solicitado no fue encontrado", details: Optional[Any] = None):
        super().__init__(
            message=message,
            code="RESOURCE_NOT_FOUND",
            status_code=404,
            details=details,
        )


class ConflictException(AppException):
    def __init__(self, message: str = "Conflicto con un recurso existente", details: Optional[Any] = None):
        super().__init__(
            message=message,
            code="RESOURCE_CONFLICT",
            status_code=409,
            details=details,
        )


class BadRequestException(AppException):
    def __init__(self, message: str = "Solicitud inválida o parámetros incorrectos", details: Optional[Any] = None):
        super().__init__(
            message=message,
            code="BAD_REQUEST",
            status_code=400,
            details=details,
        )


class TenantLockedException(AppException):
    """
    Excepción lanzada cuando el tenant está en estado SOFT_LOCK o HARD_LOCK por morosidad.
    Const. Art. 6.3 / Doc. Maestro Sec. 3.
    """
    def __init__(
        self,
        message: str = "Acceso bloqueado por estado de suscripción del comercio",
        lock_type: str = "HARD_LOCK",
        details: Optional[Any] = None,
    ):
        status_code = 403 if lock_type == "SOFT_LOCK" else 402  # 402 Payment Required
        super().__init__(
            message=message,
            code=f"TENANT_{lock_type}",
            status_code=status_code,
            details=details,
        )
