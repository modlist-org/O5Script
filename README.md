# O5Script (`.o5s`)

Ultra-fast, zero-allocation, compiled scripting language designed for in-game HUDs, real-time math expressions, and state evaluation.

---

## Features

- **Zero-Heap Core**: Fixed-size stack-allocated arrays (`[3]num`, `[2][2]num`) and bounded strings (`max_str_len = 256`, 16-byte Fat Pointers). 0 byte GC/heap overhead on evaluation hot paths.
- **Turing-Complete**:
  - Loops: `lop 10`, `lop |i| 1..20`, `lop tru`, `lop |v, idx| arr`
  - Branches: `if`, `fl` (else if), `el` (else), ternary `? :`
  - Functions: Block functions with mandatory `ret` (`fun f(a, b): num { ret a + b; }`), lambdas (`fun sq(x) => x * x;`), and recursion.
- **Tag Direct Binding**:
  - Function delegate: `tag Name => Func;`
  - Block tags: `tag Name => { ... }` (implicit return of last expression)
- **Zero Pollution**: No global built-in functions. Modules imported at compile time via `@("std")` and `@("std.math")`.
- **Cross-Platform Dual Runtime**:
  - Native Zig execution engine (`libo5script.so` / `o5script.dll`) + standalone CLI (`o5s`).
  - High-performance C# / .NET bindings (`O5ScriptEngine`).

---

## Quick Example

```o5s
con Math = @("std.math");
sta counter = 0;

// Block function with recursion (ret is mandatory)
fun factorial(n: num): num {
    if n <= 1 {
        ret 1;
    }
    ret n * factorial(n - 1);
}

// Lambda function
fun square(x: num): num => x * x;

// Direct tag delegate mapping
tag Fact5 => get_fact;

// Block tag with persistent state
tag Ticks => {
    counter += 1;
    counter
}

fun get_fact() => factorial(5);

// String interpolation
"Fact(5): {factorial(5)}, Square(9): {square(9)}"
```

---

## CLI Usage

```bash
# Run a script file
o5s script.o5s

# REPL mode
o5s
```

---

## License

[MIT License](LICENCE.md) © 2026 modlist
