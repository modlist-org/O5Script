namespace O5Script.Common;

public enum O5OpCode : byte {
    Nop = 0,
    PushNum,
    Push0,
    Push1,
    PushStr,
    Pop,
    Dup,

    LoadLocal,
    StoreLocal,
    LoadState,
    StoreState,
    LoadHost,

    CheckBounds,
    LoadLocalElem,
    StoreLocalElem,
    LoadStateElem,
    StoreStateElem,

    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Neg,

    BitAnd,
    BitOr,
    BitXor,
    BitNot,
    Shl,
    Shr,

    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,

    Not,

    Jmp,
    JmpIfZero,
    JmpIfNotZero,

    CallBuiltin,
    Call,
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
