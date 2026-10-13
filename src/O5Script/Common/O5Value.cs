using System;
using System.Globalization;

namespace O5Script.Common;

/// <summary>
/// Fast zero-allocation tagged value for O5Script execution.
/// </summary>
public readonly struct O5Value : IEquatable<O5Value> {
    public readonly double Num;
    public readonly string? Str;
    public readonly O5Type Type;

    public O5Value(double num) {
        Num = num;
        Str = null;
        Type = O5Type.Num;
    }

    public O5Value(string? str) {
        Num = 0.0;
        Str = str;
        Type = O5Type.Str;
    }

    public static O5Value FromNum(double num) => new(num);
    public static O5Value FromStr(string? str) => new(str);
    public static O5Value Zero => new(0.0);
    public static O5Value One => new(1.0);

    public bool IsTruthy => Type == O5Type.Num ? (Num != 0.0 && !double.IsNaN(Num)) : !string.IsNullOrEmpty(Str);

    public bool Equals(O5Value other) =>
        Type == other.Type && (Type == O5Type.Num ? Num.Equals(other.Num) : string.Equals(Str, other.Str, StringComparison.Ordinal));

    public override bool Equals(object? obj) => obj is O5Value other && Equals(other);

    public override int GetHashCode() =>
        Type == O5Type.Num ? HashCode.Combine((byte)Type, Num) : HashCode.Combine((byte)Type, Str);

    public static bool operator ==(O5Value left, O5Value right) => left.Equals(right);
    public static bool operator !=(O5Value left, O5Value right) => !left.Equals(right);

    public override string ToString() =>
        Type == O5Type.Num ? Num.ToString(CultureInfo.InvariantCulture) : (Str ?? string.Empty);
}
