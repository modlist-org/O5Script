namespace O5Script.Common;

/// <summary>
/// Dense byte-sized machine opcodes for O5Script stack virtual machine.
/// </summary>
public enum O5OpCode : byte {
    Nop = 0,

    // Stack operations & Literals
    PushNum,      // arg: uint16 constIndex
    Push0,        // pushes 0.0
    Push1,        // pushes 1.0
    PushStr,      // arg: uint16 stringIndex
    Pop,
    Dup,

    // Variable Slots (Machine Registers)
    LoadLocal,    // arg: uint16 localSlot
    StoreLocal,   // arg: uint16 localSlot
    LoadState,    // arg: uint16 stateSlot
    StoreState,   // arg: uint16 stateSlot
    LoadHost,     // arg: uint16 hostTagIndex

    // Arithmetic
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Neg,

    // Bitwise
    BitAnd,
    BitOr,
    BitXor,
    BitNot,
    Shl,
    Shr,

    // Comparison
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,

    // Logic
    Not,

    // Control Flow
    Jmp,          // arg: int16 relativeOffset
    JmpIfZero,    // arg: int16 relativeOffset (pops and jumps if 0.0)
    JmpIfNotZero, // arg: int16 relativeOffset (pops and jumps if != 0.0)

    // Range / Count Loop Acceleration
    LoopStep,     // arg: uint16 idxSlot, uint16 limitSlot, int16 backOffset

    // Functions & Builtins
    CallBuiltin,  // arg: uint8 builtinId, uint8 argCount
    Call,         // arg: uint16 funcIndex, uint8 argCount
    Ret,
    Halt
}

public enum O5Builtin : byte {
    Sin = 0,
    Cos = 1,
    Tan = 2,
    Asin = 3,
    Acos = 4,
    Atan = 5,
    Atan2 = 6,
    Sqrt = 7,
    Abs = 8,
    Floor = 9,
    Ceil = 10,
    Round = 11,
    Min = 12,
    Max = 13,
    Clamp = 14,
    Lerp = 15,
    Pow = 16,
    Log = 17,
    Exp = 18
}
