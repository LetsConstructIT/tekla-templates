# Value-field formulas and attribute referencing

The `formula = "..."` string on a `valuefield` is a small expression language — where a template reads the model.

## How attributes are referenced

A value field lives inside a `row` with a `contenttype` (`BOLT`, `PART`, `ASSEMBLY`, …).

- **Bare name** ⇒ the row's own object: in a `BOLT` row, `GetValue("DIAMETER")` = that bolt's diameter.
- **Dotted name** ⇒ hop to a related object first: `GetValue("ASSEMBLY.WEIGHT")`, `GetValue("NUT.WEIGHT1")`, `GetValue("PROJECT.NUMBER")`, `GetValue("HISTORY.OWNER")`, `GetValue("ASSEMBLY.MAINPART.PROFILE")`. Chains can be several hops deep; the last hop can be a UDA: `GetValue("MAINPART.USERDEFINED.PRODUCT_WEIGHT")`.

### Related-object and computed-attribute namespaces

Distinct sources a bare name will **not** reach:

| Prefix | Reads | Examples |
|---|---|---|
| `CUSTOM.` | Calculated / custom-inquiry attributes (many precast) | `CUSTOM.ELEMENT_WEIGHT`, `CUSTOM.GROSS_AREA`, `CUSTOM.WALL_NET_AREA`, `CUSTOM.PILE.INCLINATION` |
| `PROFILE.` | Cross-section dimensions parsed from the profile string | `PROFILE.HEIGHT`, `PROFILE.FLANGE_THICKNESS`, `PROFILE.WEB_THICKNESS`, `PROFILE.SUBTYPE` |
| `PRIMARY.` / `SECONDARY.` | A connection's primary / secondary part | `PRIMARY.ASSEMBLY_POS`, `SECONDARY.PART_POS` |
| `POUR_UNIT.` | Cast-in-place pour objects (usually `…USERDEFINED.…`) | `POUR_UNIT.USERDEFINED.PLANNED_START_POUR` |
| `LOGICAL_BUILDING_AREA.` | Location breakdown (LBA) structure | `LOGICAL_BUILDING_AREA.LBA_SECTION`, `…LBA_STOREY` |

Two shapes beyond simple `A.B`:

- **Sub-qualified attribute** — variant selector *after* the attribute name: `CUSTOM.ELEMENT_WEIGHT.DETERMINING` / `.REINFORCED`.
- **Deep chains** — e.g. `CUSTOM.PILE.TOP.BASEPOINT.NORTH`.

Don't guess segments — copy from a shipped template or run `scripts\Get-TeklaAttributes.ps1`.

### `CURRENT_DRAWING.` — the host drawing of a placed `.tpl`

A graphical template dropped on a drawing can read that drawing's properties from **inside a model-object row**: `CURRENT_DRAWING.TITLE`, `.SCALE1`, `.NAME`, `.REVISION.MARK`, and (the key one) `CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL`. It is a **global** attribute bound to model content types (PART, ASSEMBLY, REBAR_ASSEMBLY, CAST_UNIT, …), so a `row (contenttype=PART)` on a cast-unit drawing can compare each part against the drawing's own cast unit — the mechanism behind a BOM table on a drawing showing only *that* drawing's objects. See [rows-and-content-types.md](rows-and-content-types.md#reports-embedded-on-a-drawing). Confirm names: `scripts\Get-TeklaAttributes.ps1 -ContentType PART -Name CURRENT_DRAWING`.

**Valid names depend on content type and Tekla version — don't guess:**

```powershell
scripts\Get-TeklaAttributes.ps1 -ContentType ASSEMBLY          # all attrs, with datatype + unit
scripts\Get-TeklaAttributes.ps1 -ContentType PART -Name WEIGHT # hunt a concept
```

The `Datatype` column (`FLOAT`/`INTEGER`/`CHARACTER`) determines the valuefield `datatype`, whether `decimals` applies, and numeric-vs-string comparison. The catalog names are **not** the file keywords — map them:

| Catalog (`Get-TeklaAttributes.ps1`) | valuefield `datatype` |
|---|---|
| `FLOAT` | `DOUBLE` |
| `INTEGER` | `INTEGER` |
| `CHARACTER` | `STRING` |

Writing `datatype = FLOAT` or `CHARACTER` in a template is invalid (`-Strict` catches it).

**The `#N` suffix in catalog output is not part of the name.** `NUMBER#1` = version variant; write `GetValue("NUMBER")`. `(X)` marks a parameter you substitute. When in doubt, grep a shipped template for the base name.

## GetValue

`GetValue("ATTR")` returns the value; for numbers, the field's `datatype`/`decimals`/unit formatting applies on output. Special sources:

- `PROJECT.NUMBER`, `PROJECT.NAME` — project properties.
- `ADVANCED_OPTION.XS_LANGUAGE`, `ADVANCED_OPTION.XSDATADIR` — advanced options / env vars. `XSDATADIR` = data-dir path (useful for `fvf()` external-file paths); `XS_IMPERIAL` drives metric/imperial branching.
- `EXTERNAL.<prop>` — reference model / IFC property.
- `DATE`, `TIME`, `PAGE` — print metadata (`PAGE` = running page number, usually in `pageheader`/`footer`).
- `REVISION.LAST_MARK`, `REVISION.LAST_DATE_CREATE`, … — newest revision read straight off a `DRAWING` row, no `REVISION` child needed (see [rows-and-content-types.md](rows-and-content-types.md#drawing-list-and-revision-history-reports)).

**Formatting:** two interchangeable routes — declare on the field (`class="Weight"; unit="kg"; decimals=1`, see [file-format.md](file-format.md)) or inline:

```
format(GetValue("VOLUME"), "Volume", "m3", 2)
format(GetValue("USERDEFINED.PLANNED_START_POUR"), "Date", "dd.mm.yyyy", 10)
```

Use `format()` when the value is part of a concatenated string; use field `class`/`unit` when the field *is* the number. `format()` nests: `format(round(GetValue("LENGTH"), 5), "Length", "mm", 0)`. Fractional-unit precision is a fraction: `format(GetValue("LENGTH"), "Length", "inch-frac", 1/16)`.

**Metric/imperial dual output** — pervasive idiom; shipped templates leave field `class`/`unit` empty and branch inline on `XS_IMPERIAL`:

```
if GetValue("ADVANCED_OPTION.XS_IMPERIAL") == "TRUE" then
    format(GetValue("LENGTH"), "Length", "inch-frac", 1/16)
else
    format(round(GetValue("LENGTH"), 5), "Length", "mm", 0)
endif
```

The same guard swaps unit labels (`"inch"`/`"mm"`, `"lb"`/`"kg"`) or weight formats (`"lbf"` vs `"kg"`).

## Operators

| Operator | Meaning |
|---|---|
| `+` | numeric add **or** string concat (depends on datatype) |
| `-` `*` `/` | arithmetic |
| `==` `!=` | equality / inequality |
| `>` `<` `>=` `<=` | comparison |
| `\|\|` `&&` | logical OR / AND |

```
"GetValue(\"ASSEMBLY_POS\") + \" -> \" + GetValue(\"CONNECTED_ASSEMBLIES\")"
"(GetValue(\"WEIGHT\")+GetValue(\"NUT.WEIGHT1\")+GetValue(\"WASHER.WEIGHT1\"))*1000"
```

## Conditionals

```
if (<condition>) then <expr> else <expr> endif
```

Parens around the condition are **optional** — shipped rules often omit them. Match the surrounding file; don't "fix" a paren-less condition. Nestable; `else if` = nested `if … endif` inside the `else`:

```
if (GetValue("EXTERNAL.Reference") != 0) then
    GetValue("EXTERNAL.Reference")
else
    if (GetValue("EXTERNAL.Profile name") != 0) then
        GetValue("EXTERNAL.Profile name")
    else
        StepOver()
    endif
endif
```

Empty/unset tests: `!= 0` is the common idiom; `IsSet("ATTR")` is explicit; `== null` / `!= null` for genuinely absent string UDAs (e.g. `GetValue("CPLRSTATE_L") == null` = "no coupler on long end"). Both `!= 0` and `== null` appear in shipped rebar schedules. Newlines inside a formula are the literal two characters `\n` in the file — write the file with the Write/Edit tools, never via shell echo/heredocs, which would collapse `\n` into a real newline.

## StepOver

`StepOver()` makes the current row emit **no output** — the in-formula filter. Prefer the row's `rule` field for structural filtering (see rows-and-content-types.md); use `StepOver()` when the decision needs a computed value.

## TranslatedText

`TranslatedText("albl_Weight")` returns the label in the model's language. In files it appears wrapped in `GetValue`:

```
formula = "GetValue(\"TranslatedText(\"albl_Weight\")\")"
formula = "GetValue(\"TranslatedText(\"albl_Assembly\")\")+\": \"+GetValue(\"ASSEMBLY_POS\")"
```

Yes, the inner `albl` quotes sit at the same escape level as the quotes they're nested
inside — this deliberately violates normal nesting rules. **Copy the pattern exactly; do
not add backslashes or restructure it.** Tekla's parser special-cases this construct.

`albl_*` keys live in Tekla's localization files. Prefer `TranslatedText` for headings; a literal `text` object only when localization doesn't matter.

### Manual multi-language fields (UDA language codes)

When a title block must follow a **per-drawing/per-project** language (not the application language), shipped Finnish title blocks branch on a language-code UDA: read the drawing's `DR_LANGUAGE`, fall back to project `P_LANGUAGE`, compare the leading two-char code, print the matching literal:

```
if (mid(GetValue("CURRENT_DRAWING.USERDEFINED.DR_LANGUAGE"), 0, 2) == "01" &&   /* 01 = use project's setting */
    mid(GetValue("PROJECT.USERDEFINED.P_LANGUAGE"),          0, 2) == "02" ||    /* 02 = English */
    mid(GetValue("CURRENT_DRAWING.USERDEFINED.DR_LANGUAGE"), 0, 2) == "03")      /* 03 = English */
then <English label> else <Finnish label> endif
```

Code values are an environment convention — read them from the environment's UDA definitions, don't assume.

## Common functions

Complete version-accurate catalog with signatures: [functions.md](functions.md). If a function isn't there, it probably doesn't exist.

| Function | Purpose |
|---|---|
| `IsSet("ATTR")` | true if the attribute has a value |
| `NextValue("ATTR")` / `PreviousValue("ATTR")` | same attribute on next/previous row (de-dup) |
| `mid(str, offset, n)` / `find(str, substr)` | substring / index (combined to split marks) |
| `match(str, pattern)` | pattern test; `*` and `?` wildcards |
| `replace(src, old, new)` / `toupper` / `tolower` | string rewriting |
| `format(x, "meaning", "unit", "prec")` | explicit unit formatting (class table in functions.md) |
| `Sum("field")` / `Total("field")` | running subtotal / grand total of a named field |
| `Count("field")` / `All("field")` | running count / total count |
| `CopyField("field")` | pull a value field's value from elsewhere in the hierarchy |
| `round(x, accuracy)` | round to a step |
| `StepOver()` | emit no output for this row |

`Sum("FieldName")` totals a named value field (the field's `name = "..."`) across combined rows, resetting per output row; `Total` accumulates over the **whole** report — the "total weight" footer. These read every processed field, including hidden ones and rows dropped by a rule. **None work in row rules** — value-field formulas only.

**`GetFieldFormula("field")`** — compute once, reuse and scale: put a long `XS_IMPERIAL` branch in one field and let other columns read it back (`GetFieldFormula("field_WEIGHT_1")`, or `…*0.7` for a derived figure). Returns the formatted value, so reuse inherits the source's unit branching. A pure key field would be `visibility = FALSE`.

## Escaping quotes

The formula is itself a quoted string — escape every interior `"` as `\"`:

```
formula = "GetValue(\"PART.PROFILE\")";
```

Write the logical expression first, then escape. A missing/extra backslash is the most common reason a hand-edited template fails to open.
