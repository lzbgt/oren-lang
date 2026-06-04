# Error Function References

Scope: real-valued `std:math.erf` and `std:math.erfc` API work.

Downloaded source pages:

- `https://dlmf.nist.gov/7.1` -> `project-doc/web/math/nist_dlmf_7_1_error_functions.html`
- `https://dlmf.nist.gov/7.2` -> `project-doc/web/math/nist_dlmf_7_2_error_function_definitions.html`

Reference used:

- NIST DLMF section 7.2 defines `erf(z)` as `2/sqrt(pi) * integral_0^z exp(-t^2) dt`.
- NIST DLMF section 7.2 defines `erfc(z)` as `2/sqrt(pi) * integral_z^infinity exp(-t^2) dt = 1 - erf(z)`.

Implementation note:

- Oren v0 implements deterministic real-`f64` approximations for `erf`/`erfc` without host `libm`.
- The current kernel is a bounded five-term real approximation and is tested against stable reference values plus complement/symmetry identities.
- This is not documented as correctly rounded libm parity; a future mathlib-parity slice can replace the kernel while keeping the public API.
