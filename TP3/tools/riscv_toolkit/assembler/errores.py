"""Error del ensamblador con el número de línea de la fuente (US-106, AC4)."""


class ErrorEnsamblado(ValueError):  # noqa: N818
    """El programa no se puede ensamblar. `linea` cuenta desde 1, como en el editor."""

    def __init__(self, linea: int, mensaje: str) -> None:
        super().__init__(f"línea {linea}: {mensaje}")
        self.linea = linea
        self.mensaje = mensaje
