# O5Script (.o5s) Language Specification

O5Script is an ultra-fast, zero-allocation, Turing-complete compiled scripting language designed exclusively for in-game math expressions, HUD overlays, and real-time state evaluation.

---

## 1. Types & Variables

### Types
- `num`: 64-bit IEEE 754 floating point number (`f64`). Standard number type.
- `str`: String type for text, labels, and formatting.
- Type annotations are optional (inferred by default) but can be explicitly annotated:
  ```o5s
  let a: num = 10;
  let s: str = "hello";
  ```

### Variables & State
- `let <ident>[: <type>] = <expr>;`: Local variable (valid only within current tick/scope).
- `sta <ident>[: <type>] = <expr>;`: Persistent state variable (retains its value across frames/ticks).
- `con <ident>[: <type>] = <expr>;`: Compile-time constant (constant folded).

---

## 2. Control Flow & Loops

### Conditionals
- `if <cond> { ... }`: Conditional branch.
- `fl <cond> { ... }`: Else-if branch.
- `el { ... }`: Else branch.
- Ternary operator: `<cond> ? <then_expr> : <else_expr>`.

### Loops (`lop`)
- Infinite loop:
  ```o5s
  lop 1 { ... }
  lop tru { ... }
  ```
- Count loop (0 to count):
  ```o5s
  lop 10 { ... }
  lop |i| 10 { ... }      // captures loop index 'i' (optional |i|)
  ```
- Range loop (Zig-style):
  ```o5s
  lop 1..20 { ... }
  lop |i| 1..20 { ... }   // captures loop index 'i'
  ```
- Loop control:
  - `out`: Loop break (escape current loop).
  - `skp`: Loop continue (skip to next iteration).

---

## 3. Functions & Tags

### Functions (`fun`)
- Block functions (explicit `ret` is mandatory):
  ```o5s
  fun add(a: num, b: num): num {
      ret a + b;
  }
  ```
- Lambdas / arrow expressions:
  ```o5s
  fun add(a, b) => a + b;
  ```

### Tag Registration (`tag`)
Registers tags directly for the Overlayer engine:
- Direct delegate / function mapping:
  ```o5s
  tag Moon_CRot => rot;
  ```
- Block evaluation:
  ```o5s
  tag Moon_CRot => {
      // calculations...
      ret rot;
  }
  ```

---

## 4. Strings & Interpolation

- String concatenation with `+` is supported (`"BPM: " + #CurBpm`).
- Embedded string interpolation:
  ```o5s
  "Current BPM: {#CurBpm}"
  ```
- To output literal `{` or `}` inside strings, escape with `{{` or `}}`:
  ```o5s
  "Literal brace: {{#CurBpm}}"   // outputs: Literal brace: {#CurBpm}
  ```

---

## 5. Operators & Literals

### Operators
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Logic: `&&`, `||`, `!`
- Bitwise: `&`, `|`, `^`, `~`, `<<`, `>>`
- Comparison: `==`, `!=`, `<`, `<=`, `>`, `>=`
- Power: `pow(a, b)` function provided by standard library.

### Literals
- Numbers: `123`, `3.14159`, `.5`
- Booleans: `0` (false), `1` (true). `tru` (1) and `fls` (0) defined in standard library.
- External Host Tags: `#<TagName>` (e.g. `#CurBpm`, `#Score`, `#CamRotRad`).
- Single-line comments: `// ...`
- Multi-line comments: `/* ... */`
