// GENERADO por tools/scripts/gen_du_defs.py desde riscv_toolkit/protocol/comandos.py.
// NO EDITAR A MANO: cambiar comandos.py y regenerar.

`ifndef DU_DEFS_VH
`define DU_DEFS_VH

// Comando
`define DU_CMD_LOAD 8'h4C
`define DU_CMD_RUN 8'h52
`define DU_CMD_STEP 8'h53
`define DU_CMD_DUMP 8'h44
`define DU_CMD_RESET 8'h58
`define DU_CMD_ABORT 8'h41
`define DU_CMD_PING 8'h3F
`define DU_CMD_DUMP_MEM 8'h4D

// ErrorNack
`define DU_ERR_DESCONOCIDO 8'h01
`define DU_ERR_ESTADO 8'h02
`define DU_ERR_CHECKSUM 8'h03
`define DU_ERR_TAMANO 8'h04
`define DU_ERR_RANGO 8'h05
`define DU_ERR_TIMEOUT 8'h06
`define DU_ERR_PARIDAD 8'h07

// TipoTrama
`define DU_TIPO_ACK 8'h01
`define DU_TIPO_NACK 8'h02
`define DU_TIPO_SNAPSHOT 8'h03
`define DU_TIPO_PING_INFO 8'h04
`define DU_TIPO_MEM_DATA 8'h05

// EstadoDU
`define DU_ESTADO_IDLE 4'h0
`define DU_ESTADO_LOADING 4'h1
`define DU_ESTADO_READY 4'h2
`define DU_ESTADO_RUN 4'h3
`define DU_ESTADO_STEPPING 4'h4
`define DU_ESTADO_DUMPING 4'h5
`define DU_ESTADO_HALTED 4'h6

// Motivo
`define DU_MOTIVO_NINGUNO 4'h0
`define DU_MOTIVO_HALTED 4'h1
`define DU_MOTIVO_ILLEGAL 4'h2
`define DU_MOTIVO_ABORTED 4'h3

// Constantes
`define DU_PROTO_VERSION 8'h01
`define DU_SYNC 8'hA5
`define DU_HALT_WORD 32'h0000000B
`define DU_HALT_OPCODE 7'h0B
`define DU_IMEM_DEPTH 256
`define DU_DMEM_DEPTH 256
`define DU_RX_TIMEOUT_MS 100
`define DU_SNAPSHOT_FIJO 221
`define DU_SNAP_PALABRA_USADA 6

`endif
