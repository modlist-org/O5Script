# O5Script (`.o5s`)

Ultra-fast, zero-allocation, compiled scripting language designed for in-game HUDs, real-time math expressions, and state evaluation.

---

## Features

- **Zero-Heap Core**: Fixed-size stack-allocated arrays (`[3]num`, `[2][2]num`), flat contiguous structs (`stu`), and bounded strings (`max_str_len = 256`, 16-byte Fat Pointers). 0 byte GC/heap overhead on evaluation hot paths.
- **Zero-Cost Structures & Methods (`stu`)**:
  - Member methods with automatic `slp` (self) detection & stack relative offset passing (pass-by-reference).
  - Pure static helper methods compiled with 0 overhead when `slp` is unused.
  - Value vs Reference semantics: Default pass-by-reference (`a = b`) and explicit deep copy syntax (`a = |b|`, `fun f(a: |Point|)`).
  - Compile-time escape analysis (`LifetimeError`).
- **Control Flow & Pattern Matching**:
  - Loops: `lop 10`, `lop |i| 0..10` (half-open), `lop |i| 0..=10` (inclusive), `lop |v, idx| arr`.
  - Conditionals: `if`, `lf` (else if), `el` (else), ternary `? :`.
  - Pattern matching (`jmp`): Expression and statement matching with range (`0..=1`), single, OR (`2 | 3`), default (`_`), and dense jump table dispatch (`table_jmp`).
  - Low-level jumps: `go $label` and `$label`.
- **Functions & State**:
  - Block functions with mandatory `ret`, lambdas (`fun sq(x) => x * x;`), and recursion.
  - Function-level static variables (`sta`) retaining values across calls (C static semantics).
  - Immutable / constant parameters (`fun f(con msg: str)`).
- **Tag Direct Binding**:
  - Function delegate: `tag Name => Func;`
  - Block tags: `tag Name => { ... }` (implicit return of last expression)
- **Zero Pollution**: No global built-in functions. Modules imported at compile time via `@("std")` and `@("std.math")`.
- **Cross-Platform Dual Runtime**:
  - Native Zig execution engine (`libo5script.so` / `o5script.dll`) + standalone CLI (`o5s`).
  - High-performance C# / .NET bindings (`O5ScriptEngine`).

---

## Performance

Tested on Linux x86_64 against native Zig compiled with `-OReleaseFast` (LLVM -O3):

| Benchmark | Native Zig (`-OReleaseFast`) | O5Script (Direct-VM) | Relative Speed |
| :--- | :--- | :--- | :--- |
| **100M Loop Counter** | 212.2 ms | **209.2 ms** | **~1.0x (Equal / 1% faster)** |
| **10M Struct Method Invocations** | 20.9 ms | **61.5 ms** | **~2.9x of Native** |
| **Recursive Fib(35) [29.8M calls]** | 14.1 ms | **153.6 ms** | **~10.9x of Native** |

> *Note: For comparison on Fib(35), standard Python takes ~1,800 ms (12x slower than O5Script) and LuaJIT Interpreter takes ~550 ms (3.5x slower).*

---

## Quick Example

```o5s
con Math = @("std.math");
sta counter = 0;

// Struct with member methods (slp is automatically detected & passed by reference)
stu Counter {
    val: num,
    step: num,

    add() {
        slp.val += slp.step;
    },

    get(): num {
        ret slp.val;
    }
}

// Function with recursion and static state
fun factorial(n: num): num {
    if n <= 1 {
        ret 1;
    }
    ret n * factorial(n - 1);
}

// Pattern matching expression with inclusive ranges
fun classifyScore(score: num): str {
    ret jmp score {
        90..=100 => "A",
        80..90   => "B",
        70..80   => "C",
        _        => "F"
    };
}

// Instantiation and method mutation
let c = Counter { val: 10, step: 5 };
c.add();
let total = c.get(); // 15

// Direct tag delegate mapping
tag Fact5 => get_fact;

// Block tag with persistent state
tag Ticks => {
    counter += 1;
    counter
}

fun get_fact() => factorial(5);

// String interpolation
"Score: {classifyScore(95)}, Fact(5): {factorial(5)}, Total: {total}"
```

---

## CLI Usage

```bash
# Run a script file
o5s script.o5s

# Evaluate inline expression
o5s -e "let s = 0; lop |i| 0..=10 { s += i; } s"

# REPL mode
o5s
```

---

## License

[MIT License](LICENCE.md) © 2026 modlist
