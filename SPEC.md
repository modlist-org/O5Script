# O5Script (.o5s) Language Specification

O5Script is an ultra-fast, zero-allocation, Turing-complete compiled scripting language designed exclusively for in-game math expressions, HUD overlays, and real-time state evaluation.

---

## 1. Syntax & Keywords

### Types
- `num`: 64-bit IEEE 754 floating point number (`f64`). Standard number type.
- `str`: String type for text, labels, and formatting.

### Variables & State
- `let <ident> = <expr>;`: Local variable (valid only within current tick/scope).
- `sta <ident> = <expr>;`: Persistent state variable (retains its value across frames/ticks).
- `con <ident> = <expr>;`: Compile-time constant (constant folded).

### Control Flow
- `if <cond> { ... }`: Conditional branch.
- `fl <cond> { ... }`: Else-if branch.
- `el { ... }`: Else branch.
- `lop { ... }`: Loop construct.
- `out`: Loop break (escape current loop).
- `skp`: Loop continue (skip to next iteration).

### Functions
- `fun <name>(<args...>) { ... }`: Function declaration.

### Literals & Comments
- Booleans: `0` (false), `1` (true). Standard library defines `tru = 1` and `fls = 0`.
- External Host Tags: `#<TagName>` (e.g. `#CurBpm`, `#Score`, `#CamRotRad`).
- Single-line comments: `// ...`
- Multi-line comments: `/* ... */`
