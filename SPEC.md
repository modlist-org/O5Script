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
- Range loop:
  - Half-open range `min..max` (excludes `max`):
    ```o5s
    lop 1..20 { ... }
    lop |i| 1..20 { ... }   // captures loop index 'i' (1 to 19)
    ```
  - Inclusive range `min..=max` (includes `max`):
    ```o5s
    lop 1..=20 { ... }
    lop |i| 1..=20 { ... }  // captures loop index 'i' (1 to 20)
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
- Constant / Immutable parameters (`con`):
  Parameters can be marked immutable with `con`. Reassigning to them triggers a compile error:
  ```o5s
  fun printMsg(con msg: str) {
      // msg = "other"; // Compile error: CannotAssignToConstant
      ret msg;
  }
  ```
- Function-level static variables (`sta`):
  Variables declared with `sta` inside a function retain their values across subsequent calls (identical to C static variables):
  ```o5s
  fun counter(): num {
      sta count = 0;
      count += 1;
      ret count;
  }
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

---

## 9. Structures (`stu`) & Member Methods

O5Script structs are flat, contiguous memory layouts allocated directly on the VM execution stack. They carry **zero heap overhead** and zero garbage collection pressure.

### Declaration & Instantiation
```o5s
stu Point {
    x: num,
    y: num
}

// Named field initialization
let p = Point { x: 10, y: 20 };

// Positional field initialization
let p2 = Point { 10, 20 };
```

### Member Methods & Automatic `slp` Detection
Methods can be declared directly inside `stu` or externally with `fun StructName.method(...)`.
The compiler scans the function body for occurrences of `slp` (self):
- **If `slp` is used**: The compiler automatically injects the receiver as a pass-by-reference 0th parameter without requiring the user to declare it in the parameter list. The caller automatically pushes the relative stack offset, allowing direct, in-place mutation of caller stack fields.
- **If `slp` is NOT used**: The method is compiled as a zero-overhead static function with no receiver argument passed.

```o5s
stu Counter {
    val: num,
    step: num,

    // slp is automatically detected and injected:
    add() {
        slp.val += slp.step;
    },

    get(): num {
        ret slp.val;
    },

    // Pure helper (no slp) - compiled as static method:
    double(n: num): num {
        ret n * 2;
    }
}

let c = Counter { val: 10, step: 5 };
c.add();
let v = c.get(); // 15
```

### External Method Definition
Methods can also be attached after struct declaration:
```o5s
fun Point.translate(dx: num, dy: num) {
    slp.x += dx;
    slp.y += dy;
}
```

### Nested Structs & Chained Invocations
Structs can contain other structs as fields. Method calls and mutations chain naturally with exact relative stack frame offsets:
```o5s
stu Engine {
    rpm: num,
    rev() {
        slp.rpm += 500;
    }
}

stu Car {
    engine: Engine,
    accelerate() {
        slp.engine.rev();
    }
}

let car = Car { engine: Engine { rpm: 1000 } };
car.accelerate();
car.engine.rpm // 1500
```

---

## 10. Value vs Reference Semantics (`|x|`) & Lifetime Safety

To guarantee ultra-fast execution, **structs (`stu`) and strings (`str`) are passed and assigned by reference by default**.

### Assignment Semantics
- `a = b;`: **Reference assignment**. Modifying fields of `a` directly mutates `b`.
- `a = |b|;`: **Deep copy**. Creates a duplicate copy of `b` in `a`'s memory slots.

```o5s
let a = Point { x: 1, y: 2 };
let b = a;     // Reference
b.x = 99;      // a.x is now 99!

let c = |a|;   // Deep copy
c.x = 0;       // a.x remains 99
```

### Function Parameter Passing
- Pass-by-reference (default):
  ```o5s
  fun mutate(p: Point) {
      p.x += 10;
  }
  ```
- Deep copy:
  ```o5s
  fun process(p: |Point|) {
      // p is a full local copy; caller's struct is never affected
  }
  ```

### Compile-Time Lifetime & Scope Protection
Assigning an inner-scoped struct reference to an outer-scoped variable produces a compile-time error (`LifetimeError`), preventing dangling references:
```o5s
let outer = Point { x: 0, y: 0 };
{
    let inner = Point { x: 10, y: 20 };
    // outer = inner; // Compile error: LifetimeError
}
```

---

## 11. Pattern Matching (`jmp`)

`jmp` provides pattern matching expressions and statements with C-like dense jump table optimization.

### Syntax & Patterns
- Single value: `10 => ...`
- Multiple values (OR): `2 | 3 => ...`
- Half-open range: `min..max => ...` (matches `min <= x < max`)
- Inclusive range: `min..=max => ...` (matches `min <= x <= max`)
- Wildcard / default: `_ => ...`

```o5s
// Expression form (evaluates to result value)
let label = jmp score {
    90..=100 => "A",
    80..90   => "B",
    70..80   => "C",
    _        => "F"
};

// Statement form
jmp code {
    1 | 2 => {
        // handle 1 or 2
    }
    10..=20 => {
        // handle range 10 to 20
    }
    _ => {
        // default
    }
}
```

### Jump Table Optimization
When all case labels are dense integer literals, the compiler automatically emits a `table_jmp` opcode (direct branch table dispatch in O(1) time), completely bypassing sequential conditional comparisons.

---

## 12. Jump Statements (`go` & Labels)

For low-level control flow in state machines or unrolled algorithms:
- Labels are declared with `$<name>`.
- Jumps are executed with `go $<name>;`.

```o5s
let i = 0;

$loop_start
if i >= 10 {
    go $loop_end;
}
i += 1;
go $loop_start;

$loop_end
```

---

## 13. Performance & Architecture

- **Hardware Register Mapping**: The VM interpreter (`vm_x86_64.S`) anchors bytecode execution in dedicated x86_64 CPU registers (`r12` = Instruction Pointer, `r11` = Evaluation Stack Base, `r10` = Evaluation Stack Pointer, `rbx` = Local Frame Pointer).
- **Zero Heap / Zero GC**: All local variables, arrays, structs, and strings reside on contiguous stack memory or fixed buffers.
- **Micro-benchmark Comparison (AMD/Intel x86_64)**:
  - 100M Loop: **O5Script 209 ms** vs **Native Zig 212 ms** (O5Script is ~1% faster due to direct register-fused loop step).
  - 10M Struct Method Calls: **O5Script 61 ms** vs **Native Zig 20 ms** (~3x of native C/Zig).
  - Recursive Fib(35) [29.8M call frames]: **O5Script 153 ms** vs **Native Zig 14 ms** (Python ~1800 ms, LuaJIT Interpreter ~550 ms).


