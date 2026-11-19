# Error: x32 no existe (hay x0…x31). Los nombres ABI (sp, a0…) tampoco se aceptan (ADR-013).
        addi x1, x0, 1
        addi x32, x1, 1
        halt
