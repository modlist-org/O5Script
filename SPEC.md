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
- `lf <cond> { ... }`: Else-if branch.
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
- Block evaluation (`ret` is optional; last expression automatically returned):
  ```o5s
  tag Moon_CRot => {
      let diff = #CamRotRad - rot;
      rot + diff * 0.5
  }
  ```

---

## 4. Evaluation Semantics

- **Inline Expressions & Blocks (`{ ... }`)**:
  `ret` is completely optional. The value of the last evaluated expression is automatically returned as the result:
  ```o5s
  {
      let speed = #CurBpm;
      speed > 300 ? "FAST" : "NORMAL"
  }
  ```
- **Explicit `ret`**:
  `ret <expr>;` is supported for early return from functions or blocks.

## 5. Strings & Interpolation

- **Bounded Length (Zero-Heap)**:
  - Strings are strictly non-heap, bounded by a compile-time and runtime limit of 256 bytes (`max_str_len = 256`).
  - Literal strings exceeding 256 bytes fail with compile error `StringLiteralTooLong`.
  - Dynamic string concatenation exceeding 256 bytes fails with runtime error `StringTooLong`.
- **Host Tag Strings**:
  - Host strings (e.g. `#SongTitle`, `#Artist`) are passed as zero-copy 16-byte Fat Pointers (`str_ptr` + `str_len`). Zero allocations, zero copies, O(1) pointer reference.
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

## 6. Operators & Literals

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

---

## 7. Modules & Imports (`@`)

O5Script has **no global built-in functions** to prevent scope pollution and maintain strict zero-cost abstractions. All math and system utilities must be explicitly imported via compile-time module bindings using `@("...")`.

### Module Syntax
- Import standard library:
  ```o5s
  con Std = @("std");
  con Math = Std.Math;
  ```
- Direct submodule import:
  ```o5s
  con Math = @("std.math");
  ```

### `Std.Math` Functions & Constants
- Functions: `Math.sin(x)`, `Math.cos(x)`, `Math.tan(x)`, `Math.asin(x)`, `Math.acos(x)`, `Math.atan(x)`, `Math.atan2(y, x)`, `Math.sqrt(x)`, `Math.abs(x)`, `Math.floor(x)`, `Math.ceil(x)`, `Math.round(x)`, `Math.min(a, b)`, `Math.max(a, b)`, `Math.clamp(v, min, max)`, `Math.lerp(a, b, t)`, `Math.pow(a, b)`, `Math.log(x)`, `Math.exp(x)`
- Constants (compile-time folded): `Math.pi`, `Math.e`, `Math.tau`

---

## 8. Fixed-Size Arrays (Zig-Style)

Arrays are allocated purely as contiguous stack slots in the VM frame with zero heap allocation. Dynamic resizing (`push`/`pop`) is prohibited by design.

### Array Declaration & Types
- Type annotations: `[N]num`, `[N]str`, multi-dimensional `[N][M]num`.
- Untyped literal (type-inferred):
  ```o5s
  let a = [10, 20, 30];
  let m = [[1, 2], [3, 4]];
  ```
- Zig-style typed literal:
  ```o5s
  let a: [3]num = [3]num{ 10, 20, 30 };
  let m = [2][2]num{ [1, 2], [3, 4] };
  ```

### Indexing & Mutation
- Zero-based indexing: `a[0]`, `m[1][0]`.
- Element assignment & compound operators:
  ```o5s
  a[1] = 99;
  a[1] += 1;
  ```
- **Bounds Checking**:
  - Static out-of-bounds index: compile error (`IndexOutOfBounds`).
  - Dynamic out-of-bounds index: runtime error (`OutOfBounds` trap).

### Length Property (`.len`)
- Compile-time folded zero-cost length access:
  ```o5s
  let len = a.len;       // 3
  let rows = m.len;      // 2
  ```

### Array Iteration (`lop`)
- Iterating values:
  ```o5s
  let sum = 0;
  lop |v| a {
      sum += v;
  }
  ```
- Iterating with value and index:
  ```o5s
  let sum = 0;
  lop |v, i| a {
      sum += v * i;
  }
  ```

