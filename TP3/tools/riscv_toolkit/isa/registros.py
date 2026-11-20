"""Nombres de los 32 registros (`x0`…`x31`) y su número, para los campos rd/rs1/rs2 (US-105).

Solo nombres por número: los nombres ABI (`t0`, `sp`, …) no se aceptan (ADR-013).
"""

from typing import Final

REGISTROS: Final[dict[str, int]] = {f"x{i}": i for i in range(0, 32)}
