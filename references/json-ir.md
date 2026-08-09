# JSON IR — the deterministic authoring pipeline

The safest way to *create or machine-edit* a template is not to write `.rpt`/`.tpl` text
at all: author **JSON**, validate it against a **JSON Schema**, and let a fixed emitter
produce the template text.

```
JSON IR ──schema gate──▶ ConvertTo-TeklaTemplate.ps1 ──▶ canonical .rpt/.tpl ──▶ -Strict / preview
   ▲
   └── ConvertFrom-TeklaTemplate.ps1 ◀── any existing template   (lossless round trip)
```

Why this beats writing template text directly:

- **The crash classes are unreachable, not just detected.** The emitter's layout is fixed
  (CRLF, leading blank line, 4-space indent, one statement per line, `{` and `};` on their
  own lines, no comments) — exactly what TplEd itself writes. Packed formatting, structural
  comments, and bare-LF endings *cannot be produced*.
- **Structure is machine-checked before a single byte is emitted.** The schema rejects an
  invented block type, an invented property key, a wrong enum value, a wrong tuple arity,
  a block nested where it can't go, and a missing always-written property.
- **Determinism.** The same JSON always emits byte-identical template text. No formatting
  drift, no escaping accidents, clean diffs.

## The scripts

| Script | Direction | Notes |
|---|---|---|
| `scripts\ConvertFrom-TeklaTemplate.ps1` | `.tpl`/`.rpt` → `<file>.json` | lossless; use it to edit existing templates through JSON |
| `scripts\ConvertTo-TeklaTemplate.ps1` | JSON → `.tpl`/`.rpt` | gates: schema → emit → re-parse; `-Strict` adds the grammar/portability lint; `-Out` names the target (default: strip `.json`, extension from `props.type`) |
| `scripts\New-TeklaTemplateSchema.ps1` | grammar census → `assets\template-schema.json` | regenerate after re-harvesting the grammar for another Tekla version |
| `tests\Test-TeklaTemplateRoundTrip.ps1` | corpus proof (development only — not part of any authoring workflow) | parse → IR → emit → re-parse must be tree-identical for every file; `-SchemaAll` also schema-validates every IR |

Shared plumbing: `scripts\_TemplateIR.ps1` (one emitter + one quoting decision used by both
directions), on top of `_TemplateParser.ps1`.

## IR shape

A template is a tree of blocks; each block is:

```json
{
  "block": "valuefield",
  "id": "_tmp_3",
  "props": { "name": "PROFILE", "location": [10, 0], "justify": "LEFT", "length": 17 },
  "children": [ ]
}
```

- `block` — the block keyword (`template`, `row`, `valuefield`, `text`, …). Required.
- `id` — the optional bare token after the keyword (`row _tmp_0`). Omit when absent.
- `props` — properties in emission order. Omit when empty.
- `children` — nested blocks in order. Omit when empty.
- The root object is the `template` block itself (a `$schema` key is tolerated there).

### Value forms

| JSON | Emitted as | Example |
|---|---|---|
| number | bare number | `"width": 78` → `width = 78;` |
| `true` / `false` | `TRUE` / `FALSE` | `"visibility": true` → `visibility = TRUE;` |
| array | tuple | `"location": [10, 0]` → `location = (10, 0);` |
| string | **bare enum keyword or quoted string — decided from the corpus kind census** | `"justify": "LEFT"` → `justify = LEFT;` but `"name": "LEFT"` → `name = "LEFT";` |
| `{"ident": "X"}` | force bare keyword | escape hatch |
| `{"string": "X"}` | force quoted string | escape hatch |
| `{"number": 1.5}` | force number | escape hatch |

The bare-vs-quoted decision is a pure function of `(block, prop, value)` over
`assets\template-grammar.json`, which records how every property is *written* in the
shipped corpus (its token **kind**: `ident` / `string` / `number` / `tuple(...)`). The
2026.0 census shows **zero** properties written both ways — quoting is fully determined —
so plain JSON strings are always enough in practice. The override objects exist for
out-of-corpus edge cases, and `ConvertFrom-` emits them automatically wherever a source
file's form ever disagrees with the canonical decision: that is what makes the round trip
lossless **by construction** rather than by convention.

Formula strings need only JSON's own escaping — no shell layer, no doubled quoting:

```json
"formula": "GetValue(\"PROFILE\")"
```

becomes `formula = "GetValue(\"PROFILE\")";` with the template-level `\"` escaping applied
by the emitter. This kills the classic hand-authoring error class where the three escaping
layers (shell → template → formula) get mixed up.

## The schema gate

`assets\template-schema.json` (JSON Schema draft 2020-12, used by `Test-Json`) is
**generated, not hand-written** — a pure function of the grammar census:

- block defs with `additionalProperties: false` — an invented key or block type fails;
- `enum` only for the same closed vocabularies `-Strict` enforces (`justify`, `datatype`,
  `oncombine`, `sorttype`, `sortdirection`, `type`, `filldirection`, `fillpolicy`,
  `fillstartfrom`, `outputpolicy`) and for booleans (`TRUE`/`FALSE`, JSON booleans OK) —
  free content (formulas, names, `USERDEFINED.*`, `ADVANCED_OPTION.*`) is never enumerated;
- tuple arities (`location` = exactly 2 numbers, `margins` = 4, …);
- `required` = the properties present in 100 % of that block's corpus instances (what
  TplEd itself always writes — omit them and TplEd's behaviour is untested territory);
- per-parent child lists (a `valuefield` can't sit directly under `template`, …).

Validate manually any time with:

```powershell
Test-Json -Json (Get-Content my.rpt.json -Raw) -SchemaFile assets\template-schema.json
```

`ConvertTo-TeklaTemplate.ps1` runs this gate automatically (skip only with `-NoSchema`),
then **re-parses its own output** before writing, and with `-Strict` also runs the
grammar allow-list + TplEd portability lint on the result.

## Authoring workflow (create a new template)

1. `ConvertFrom-TeklaTemplate.ps1` the nearest skeleton in `assets\` (or a shipped
   template found with `Find-TeklaTemplateExamples.ps1`) to get a valid JSON starting
   point — same rule as for text editing: never start from a blank `template` header.
2. Edit the JSON: rows, fields, formulas. Verify attribute names with
   `Get-TeklaAttributes.ps1` — the schema cannot know whether `PART.WEIGTH` is a typo,
   that stays your job (see `references/attribute-cookbook.md`).
3. `ConvertTo-TeklaTemplate.ps1 my.rpt.json -Strict` — schema gate, emit, lint.
4. Preview (`Render-TeklaTemplate.ps1`) and install (`Install-TeklaTemplate.ps1`) as
   usual. The emitted file is already CRLF; install re-normalizes harmlessly.

To edit an *existing* template through JSON: `ConvertFrom-…` → edit → `ConvertTo-…`. The
emitted file is the canonical form of the original (semantically identical parse tree; the
layout may be normalized).

## Version coupling and regeneration

Census, schema, and validator must describe the same Tekla version. After
`Get-TeklaGrammar.ps1 -TeklaRoot C:\TeklaStructures\<version>` (~15 min, once per
version), immediately rerun `New-TeklaTemplateSchema.ps1` (instant). The round-trip proof
(`tests\Test-TeklaTemplateRoundTrip.ps1`; ~1 h over the full corpus with `-SchemaAll`, point
`-Path` at a subtree for a quick pass) is the regression suite for any change to the
parser, IR library, census, or schema generator — run it after touching any of them; it
must report zero `mismatch`/`lint`/`schema` findings (`parse-fail` covers the handful of
genuinely malformed shipped files that every tool skips). Proven at 2026.0: 2,686 of
2,686 parseable shipped templates round-trip tree-identical, with zero schema rejections.

## Limits — what the pipeline does NOT check

- **Attribute names**: `GetValue("PROFILE")` vs `GetValue("PROFIILE")` — both are valid
  strings. Use `Get-TeklaAttributes.ps1` / the attribute cookbook.
- **Formula syntax**: the formula is one opaque string to the IR. `-Strict` and the
  preview catch some classes; final truth is Tekla.
- **Layout sense**: overlapping columns, fields past the width — that's the preview's job.
- **Graphical valuefield name collisions**: caught by `-Strict` / `Test-TeklaTemplates.ps1`
  (rule runs on the emitted file), not by the schema.
