# `modf` Reference

Scope: real-valued `std:math.modf`.

Downloaded source page:

- `https://en.cppreference.com/w/c/numeric/math/modf` -> `project-doc/web/math/cppreference_c_math_modf.html`

Reference used:

- `modf` decomposes a floating-point value into integral and fractional parts.
- Both parts have the same sign as the input value.

Implementation note:

- Oren returns `[fractional, integral]` instead of using an output pointer.
- NaN follows Oren `std:math` convention and returns `oren_err`.
- Infinity returns numeric zero for the fractional part and the original infinity for the integral part.
- Current bytecode/runtime paths normalize signed zero in several places, so signed-zero
  preservation is intentionally not part of the v0 `modf` fixture contract.
