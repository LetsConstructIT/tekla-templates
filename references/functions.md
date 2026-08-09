# Template formula function catalog

Complete function/operator set of the Template Editor formula-and-rule language. Regenerate
per-machine with `scripts\Get-TeklaTemplateInfo.ps1 -Functions`.

Conventions: `"ATTR"` = global/free attribute name, `"field"` = a value field's `name`,
`x`/`number` = numeric expression. In `.rpt`/`.tpl` files every interior `"` is
backslash-escaped (see [formulas.md](formulas.md#escaping-quotes)).

<a id="attribute-functions"></a>
## Attribute functions — read the model

Parameter is an attribute name in `" "`. Dotted names hop to a related object
(`GetValue("ASSEMBLY.WEIGHT")`). Special: `CONTENTTYPE` returns the row's content type;
prefix `CURRENT_DRAWING.` reads the drawing a graphical template is placed on — see
[formulas.md](formulas.md#current_drawing--the-host-drawing-of-a-placed-tpl).

| Function | Purpose |
|---|---|
| `GetValue("ATTR")` | Value for the **current** row's object. The workhorse. |
| `NextValue("ATTR")` | Value on the **next** (not-yet-output) row — suppress duplicate rows. |
| `PreviousValue("ATTR")` | Value on the **previous** output row. |
| `IsSet("ATTR")` | `TRUE` if a value has been set (typically user-defined free attributes). |

<a id="value-field-functions"></a>
## Value-field functions — read other fields

Operate on other value fields by name, across all processed fields — including hidden fields
and dropped rows. **Not available in row rules.**

| Function | Purpose |
|---|---|
| `Sum("field")` | **Intermediate** sum — accumulates the field's processed values, resets to zero each time the row holding the `Sum` field outputs. |
| `Total("field")` | **Grand** total across all processed values. Canonical for totals footers. |
| `Count("field")` | **Intermediate** count — the counting analog of `Sum`. On a detail row this prints the running item number (the shipped "No." column idiom — see recipes.md). |
| `All("field")` | **Total** count across the whole template — the counting analog of `Total`. |
| `CopyField("field")` | Copy a summary field's value from elsewhere in the hierarchy (even hidden rows). Search order: same row → up → rows after → rows before. Field using it cannot be sorted. |
| `GetFieldFormula("field")` | Current value of another value field; combine field formulas. |

**Decision rule** (TplEd 2026.0 Help + shipped system reports): `Sum`/`Count` are the
*resetting* pair, `Total`/`All` the *report-wide* pair. The reset fires when the row
holding the field outputs — that's what makes `Sum` a per-group subtotal in a repeating
`SUMMARY` band and a per-page subtotal in a page footer. In a report footer that outputs
**once**, `Sum` happens to equal `Total` — write `Total` anyway; shipped system reports
use `Total` exclusively for grand totals (21 footer `Total()` calls, zero footer `Sum()`).
Reach for `Sum` only when you *want* the since-last-output subtotal.

<a id="control-functions"></a>
## Control functions — steer row output

Used in conditionals in **row rules**; take no parameters. `IsFirst`, `IsLast`, `PageBreak`
also valid in value-field formulas. Hand-written formulas use empty parens (`StepOver()`);
the rule dialog omits them — both accepted.

| Function | Effect |
|---|---|
| `Output` | Output the current row. |
| `StepOver` | Skip current row, continue to next. The standard "drop this row". |
| `StepIn` | Process rows **below** in the hierarchy. |
| `StepOut` | Stop row and everything below; continue with the row **higher** up. |
| `IsFirst` / `IsLast` | `TRUE` on first / last row. |
| `PageBreak` | Insert a page break. |

**Color override:** `Output("#VFC=<color>;#TXC=<color>;#DRC=<color>;")` — value-field / text /
drawing-object color; palette indices per `colors=` in [file-format.md](file-format.md).

<a id="conditionals-and-operators"></a>
## Conditionals and operators

```
if (<condition>) then <expr> else <expr> endif
```

| Operator | Meaning |
|---|---|
| `+` `-` `*` `/` | Arithmetic; `+` on strings = concatenation. |
| `==` `!=` | Equal / not equal. |
| `<` `<=` `>` `>=` | Comparison (numeric or string). |
| `&&` `\|\|` | Logical AND / OR. |

`!= 0` is the common idiom for "attribute is set/non-empty"; `IsSet("ATTR")` is explicit.

<a id="data-type-conversion"></a>
## Data-type conversion

Types: **integer**, **double**, **string**, **vwu** (value-with-unit).

| Function | Purpose |
|---|---|
| `int(value)` | To integer — **truncates** (`3.5` → `3`); `round` first if rounding wanted. |
| `double(value)` | To double. |
| `string(value, MinDec, MaxDec)` | To string; decimals optional, doubles only; `MaxDec` defaults to `MinDec`. `string(3.14, 1)` = `"3.1"`. |
| `vwu(value, "unit")` | Value **in named unit** → display unit. Units: `ft in m cm mm rad deg`. `vwu(4.0, "in")` → `101.60` mm. |
| `format(value, "meaning", "unit", "precision")` | Formatted string, e.g. `format(GetValue("LENGTH"), "Length", "inch-frac", "1/8")` — args from the [class table](#datatypes-units-precisions). |

<a id="string-operations"></a>
## String operations

Set the field's **Data type = Text**. Take attribute/value-field functions as parameters, not
raw attributes. Offsets are **0-based**.

| Function | Purpose |
|---|---|
| `find(string, substring)` | Offset of substring. |
| `match(s1, s2)` | `TRUE` if equal. Wildcards: `?` = 0-or-1 char, `*` = 0-or-more. |
| `mid(string, offset, n)` | `n` chars from offset; omit `n` = to end. |
| `length(string)` | Character count. |
| `getat(string, offset)` / `setat(string, offset, char)` | Get / replace char at offset. |
| `replace(source, old, new)` | Replace **all** occurrences. |
| `reverse(string)` | Mirror. |
| `toupper` / `tolower` | Change case. |
| `asc(string \| int)` | String → char code of first letter; int → character. |
| `join(separator)` | Join a `CopyField` list, **dropping** empty items. |
| `join2(separator)` | Same, **keeping** empty items (`7;7;;10`). |
| `newline()` (or `\n`) | Line break — **value-field formulas only**. |
| `fvf(file, key, col, "seps", allowEmpty)` | External text-file lookup: row whose first field = `key`, return column `col`. `allowEmpty=TRUE` keeps consecutive separators as empty columns. |

<a id="math-miscellaneous"></a>
## Math / miscellaneous

| Function | Purpose |
|---|---|
| `round(number, accuracy)` | e.g. `round(x, 0.01)`. |
| `fabs` / `sqrt` / `pow(base, power)` / `exp` / `ln` / `log` | Abs, √, exponentiation, e^x, log-e, log-10. |
| `mod(dividend, divisor)` | Remainder. |
| `hypot(a, b)` | √(a²+b²). |
| `n!(number)` | Factorial. |
| `and(p1, p2)` / `or(p1, p2)` | **Bitwise** AND / OR. |

<a id="statistical"></a>
## Statistical

Take a list `x, y, z, …`: `ave` · `min` / `max` · `sqsum` (sum of squares) · `sqave` (average
of squares). Also `ceil(x)` (round up), `floor(x)` (round down).

<a id="trigonometric"></a>
## Trigonometric

Angle unit by argument prefix: `d` = degrees, `r` = radians (default), `g` = gradians —
`sin(d180)`, `sin(3.14)`, `sin(g200)`.

`sin cos tan` · `asin acos atan` (inverse, return radians) · `sinh cosh tanh` ·
`atan2(y, x)` (vector direction angle, radians).

<a id="localization"></a>
## Localization

`TranslatedText("albl_Key")` returns a label in the model's language (keys in Tekla `.ail`
files). Resolved through `GetValue`, so it appears wrapped in files — see
[formulas.md](formulas.md#translatedtext).

<a id="datatypes-units-precisions"></a>
## Value-field datatypes, units and precisions

A value field's **class** ("meaning") governs its units/precisions — the same values `format()`
takes. Authoritative list: `…\TplEd\settings\valuefieldclasses.lst`; regenerate with
`scripts\Get-TeklaTemplateInfo.ps1 -Datatypes`. Common classes:

| Class (meaning) | Units | Precisions |
|---|---|---|
| `Length`, `DistanceList` | mm, cm, dm, m, inch, ft, yd, inch-frac, ft-frac | 1/2 … 1/64 (`*-frac`) |
| `Area` | mm2, cm2, dm2, m2, sq.inch, sq.ft, sq.yd | — |
| `Area/length` | mm2/m, cm2/m, m2/m, in2/in, in2/ft, ft2/ft, sq.yd/ft | — |
| `Volume` | mm3, cm3, dm3, m3, cu.in, cu.ft, cu.yd | — |
| `Weight` | kg, T, N, lbf, kip | — |
| `Weight/length` | kg/m, T/m, N/m, daN/m, kN/m, lbf/ft | — |
| `Density` | kg/m3, T/m3, N/m3, kN/m3, lbf/ft3 | — |
| `Angle` | Degrees, radians | — |
| `Force` | kg, T, N, daN, kN, lbf, kip | — |
| `Moment` | kgm, Tm, Nm, daNm, kNm, lbf-in, lbf-ft, kip-in, kip-ft | — |
| `Stress` | …/m2, …/cm2, …/mm2 (kg,T,N,daN,kN), psi, psf, ksi, ksf | — |
| `Section_modulus` | mm3, cm3, in3 | — |
| `Moment_of_inertia` | mm4, cm4, in4 | — |
| `Date` / `Date_local` | dd.mm.yyyy, mm/dd/yyyy, yyyy-mm-dd, dd-mm-yy, … | — |
| `Time` / `Time_local` | hh:mm:ss, hh:mm:ss:am/pm | — |
| `Temperature` | Kelvin, Celsius, Fahrenheit | — |

(Also: `Warping_modulus`, `Force/length`, `Force/area`, `Moment/length`, `Date&&Time`,
`LeadingZeroes`, HVAC classes `MassFlow`, `VolumeFlow`, `HeatCapacity`, `PressureLoss`,
`Velocity`, `FlowCoefficient`, `DynamicViscosity`, `Power`, `KinematicViscosity`.) Match
`datatype`/`decimals`/unit to the attribute's class — the attribute extractor's
`Datatype`/`Unit` columns tell you which.
