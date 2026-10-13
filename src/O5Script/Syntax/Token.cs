namespace O5Script.Syntax;

public enum TokenType {
    Eof,
    Number,
    String,
    StringPart,
    Identifier,
    HostTag,

    Let,
    Sta,
    Con,
    If,
    Fl,
    El,
    Lop,
    Out,
    Skp,
    Fun,
    Ret,
    Tag,
    TypeNum,
    TypeStr,

    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    AndAnd,
    OrOr,
    Bang,
    Amp,
    Pipe,
    Caret,
    Tilde,
    LessLess,
    GreaterGreater,
    EqualEqual,
    BangEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    Equal,
    PlusEqual,
    MinusEqual,
    StarEqual,
    SlashEqual,
    Arrow,
    Dot,
    DotDot,
    At,
    Question,
    Colon,

    LParen,
    RParen,
    LBrace,
    RBrace,
    LBracket,
    RBracket,
    Comma,
    Semicolon
}

public readonly struct Token {
    public readonly TokenType Type;
    public readonly string Text;
    public readonly double NumberValue;
    public readonly int Index;
    public readonly int Length;

    public Token(TokenType type, string text, int index, int length, double numberValue = 0) {
        Type = type;
        Text = text;
        Index = index;
        Length = length;
        NumberValue = numberValue;
    }

    public override string ToString() => $"{Type}('{Text}') @ {Index}";
}
