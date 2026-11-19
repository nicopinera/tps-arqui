# Lazo infinito (ADR-010): nunca llega a un halt. En modo continuo solo se corta con ABORT
# desde la Debug Unit; el golden model termina con TIMEOUT. x1 cuenta las vueltas.
        addi x1, x0, 0
lazo:
        addi x1, x1, 1
        j    lazo
        halt                    # nunca se llega
