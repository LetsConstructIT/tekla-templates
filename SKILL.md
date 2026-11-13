---
name: tekla-templates
description: >-
  Author, generate, edit, and debug Tekla Structures Template Editor templates —
  the .rpt files behind reports (part/assembly/bolt/material lists, BOMs) and the
  .tpl files behind drawing tables (title blocks, revision tables, drawing
  lists). Use for Template Editor / tpled, value fields, content attributes
  (PART.PROFILE, ASSEMBLY.WEIGHT, GetValue formulas), row rules/filters,
  COMBINE/DISTINCT sorting, creating a report from a description, adding or
  fixing a column, Excel/CSV report output, or diagnosing a blank/truncated/
  garbled field. Trigger even
  when the user just says "report", "list", "table", "title block", or
  "template" in a Tekla context. Covers editing template TEXT; for C#/Open API
  automation of the model or drawings use the tekla-open-api skill.
---

# Tekla templates

Report templates (`.rpt`, textual) and drawing-table templates (`.tpl`, graphical) are
plain-text declarative files sharing one grammar. Read, generate, and edit them directly —
the Template Editor GUI is not required.

**Default way of working: the JSON IR pipeline** (section "Deterministic creation" below) —
author or edit templates as JSON and let the fixed emitter write the file. Hand-writing
template text is the fallback for small in-place tweaks to an existing file, and everything
below about attributes, grammar, crash traps, exemplars, preview, and install applies to
both paths.

**All `scripts\…` paths below are relative to this skill's own directory** (the folder
containing this SKILL.md), not your working directory. Your CWD is usually the user's
project, so prefix every invocation with the skill directory, e.g.
`& "<skill-dir>\scripts\Get-TeklaAttributes.ps1" …`.

## Step 1 — first-run setup: run it for the user, don't hand them commands

**Do this before anything else in a session.** Two data assets are generated from the local
Tekla install rather than shipped: `assets\template-grammar.json` (loaded by `-Strict`) and
`assets\template-index.json` (loaded by `Find-TeklaTemplateExamples.ps1`);
`assets\template-schema.json` is derived from the grammar. One script builds whatever is
missing — **just run it yourself**, without asking, whenever the user asks to
prepare/set up/initialise the skill or whether it's ready, or any script reports a missing
asset:

```powershell
scripts\Initialize-TeklaTemplates.ps1          # build what's missing (~2 min, once per Tekla version)
scripts\Initialize-TeklaTemplates.ps1 -Check   # status only; exit 0 = ready, 1 = setup needed
scripts\Initialize-TeklaTemplates.ps1 -Force   # rebuild after a Tekla upgrade
```

Safe to re-run — present-and-current assets are skipped. It auto-detects the newest install
(`C:\TeklaStructures\<version>`, then Program Files); `-TeklaRoot` pins a version and `-Path`
folds in a firm library or substitutes for a missing install. Tell the user which Tekla
version it built against. If it reports assets built from a **different** version than the
one installed, say so and offer `-Force` — it won't refresh them on its own.

**Optional fourth asset — attribute meanings.** `references\attribute-definitions.md` is
built from Trimble's per-version *"Template attributes in drawing and report templates"* PDF
(`TS_TEA_<year>_<lang>_Template_attributes.pdf`, downloadable from Tekla User Assistance).
Setup picks it up from the skill folder or `~\Downloads`, or pass `-AttributePdf <pdf>`. It is
Trimble's text, so it's gitignored and never shipped. If it's missing, tell the user once that
attribute meanings will be marked unverified until they supply the PDF.

Setup is not a precondition for working: authoring, preview, and install all work without
these files. Only `-Strict` grammar validation, the JSON-IR schema gate, and shipped-corpus
search degrade — so when setup can't complete (no Tekla on this PC), carry on and say which
checks are unavailable.

## Attributes and grammar words are not guessable — validate

Valid value-field attributes ship inside each Tekla install and vary by version. Never
invent one from memory:

```powershell
scripts\Get-TeklaAttributes.ps1 -ContentType PART -Name WEIGHT   # verify one attribute
scripts\Get-TeklaAttributes.ps1 -ContentType ASSEMBLY            # all attributes for a content type
```

Auto-detects the newest install under `C:\TeklaStructures`; `-TeklaRoot` pins a version.
Tell the user which version the catalog came from.

**"No attributes matched" does not always mean you invented it.** Two prefixes resolve at
runtime and are absent from the global catalog, so a default run wrongly denies them:
`USERDEFINED.<uda>` (UDAs — used in **646 of the 2,686** shipped templates) needs
**`-IncludeUserDefined`**, and may still be missing if the UDA is defined in a project's
`objects.inp`; `ADVANCED_OPTION.XS_*` (353 templates, e.g. the standard `XS_IMPERIAL`
branch) is in **no** catalog at all. Don't delete either on the extractor's say-so.

**A valid name is not a known meaning.** The extractor proves an attribute *exists* (name,
datatype, unit, bindings) — it says nothing about what the value represents, and neither do
names, Inquire/report labels, or shipped usage. `WELD_ACTUAL_LENGTH1` sits under the label
"Actual length" in Tekla's own weld inquiry report, yet it's the full seam length *including*
the gaps of an intermittent weld. Before stating what an attribute means, or picking one on
the strength of its meaning, look it up:

1. `references\attribute-glossary.md` (always shipped) has our own descriptions of the 300
   attributes the shipped templates use most, with traps. Grep the name as typed.
2. `references\attribute-definitions.md` (built locally from Trimble's PDF, may be absent)
   holds Trimble's full text. Grep the bare name (no `ASSEMBLY.`/`MAINPART.` prefix) and cite
   the §. Where it is more specific than the glossary, it wins.

If neither has it, or the entry is marked *(unverified)*, say the meaning is **unverified,
inferred from the name/label**, and suggest checking one known object with Inquire in the
model before the report is trusted. Never present an inferred meaning as fact.

The extractor verifies a name but won't help you *choose* one. For "the user said **piece
mark** / **grade** / **lot** — what do I type?", the traps that silently produce a wrong
number (`GRADE` is not a part's grade; `PART` binds `CLASS_ATTR` not `CLASS`; an ASSEMBLY
has no `NAME`; `MODEL_TOTAL` ignores your filters), and the ~30 most-used attributes per
content type ranked by real corpus usage, read **`references/attribute-cookbook.md`**.
`scripts\Get-TeklaTemplateInfo.ps1` lists the install's valid content types,
datatype/unit/precision classes, and documented functions (`-Datatypes`, `-Functions`).

The block/field grammar is likewise a fixed vocabulary: block types (`valuefield`, `text`,
`lineorarc`, …) and property keys (`location`, `length`, `justify`, …). An invented key
doesn't error — Tekla silently ignores it. **`-Strict`** (on the preview script below)
checks every block type, property key, and closed-enum value against
`assets/template-grammar.json` — harvested from Tekla **2026.0**'s ~2,700 shipped
templates — with nearest-match suggestions, and exits 2 on findings so it can gate
delivery. Run it on every generated or edited template. A construct missing from the
corpus reads as "verify", not "definitely wrong". Regenerate for another version with
`scripts\Get-TeklaGrammar.ps1 -TeklaRoot C:\TeklaStructures\<version>` (~30 s — once per
Tekla version, not per template); `-GrammarFile <path>` points `-Strict` at a custom list.

**TplEd crash traps** — four things make Template Editor **crash silently on open** (stack
overflow, exception `0xc0000409`, no dialog), and all are invisible to the parser here
(it is whitespace-insensitive and normalizes the file), so only the `-Strict` raw-text lint
catches them:

1. A **structural comment** (`//` or `/* … */` outside a quoted formula/rule string). TplEd
   has no block-level comment syntax. **Never put comments between blocks**; `//` is valid
   only inside a formula string.
2. **Bare-LF (Unix) line endings.** TplEd's parser assumes Windows **CRLF**; every shipped
   template is CRLF. The Write/Edit tools emit LF, so a freshly authored template will crash
   TplEd until converted. `Install-TeklaTemplate.ps1` **normalizes to CRLF automatically on
   install**, so an installed template is always safe; convert to CRLF before opening a file
   directly in TplEd from your working copy.
3. **Packed / compact formatting.** TplEd's parser requires **one statement per line**, and
   the block keyword and its `{` each on their **own** line. Two `name = value;` assignments
   on one physical line, or an inline block-open like `text { name = "x"; … };`, crash it —
   this is confirmed live (expanded file opens, byte-identical packed file `0xc0000409`) and
   by the corpus: across **all 2,689 shipped 2026.0 templates there is not one packed line**.
   CRLF normalization on install does **not** fix packing, so a packed template crashes even
   after install. **Write every property and every `{`/`}` on its own line** — the skeletons'
   compact `text { … }` one-liners are the tempting trap; expand them. (Historical note: an
   earlier read of the corpus wrongly cleared compact formatting as harmless. It is not.)
4. **Template `notes` longer than 120 characters.** The `template` header's `notes` field
   is a fixed 120-char buffer in TplEd; a longer value crashes it. The temptation is to
   use `notes` as embedded documentation (there is no comment syntax, so it's the only
   free-text slot) — **don't**: keep `notes` to a one-liner ≤ 120 chars and put longer
   documentation in an external file or the delivery notes.

**Batch-validate a whole tree** (template library, shipped environment):

```powershell
scripts\Test-TeklaTemplates.ps1 -Path D:\FirmTemplates             # parse + -Strict grammar, per file
scripts\Test-TeklaTemplates.ps1 -Path D:\FirmTemplates -NoGrammar  # parse-ability only
```

Buckets every `.tpl`/`.rpt` into clean / parse-fail / grammar-finding / `tpled-incompat`
(structural comments, bare-LF endings, packed formatting, **or notes > 120 chars** — the
four open-crash traps above); exit code 0/1/2. Use `-NoGrammar` when checking the same install the
allow-list was harvested from — the grammar check is circular there.

## Template shape

```
template { type = TEXTUAL|GRAPHICAL; ... }          // page setup
    pageheader / header                             // column titles / fixed top
    row (contenttype=PART) {                        // repeats per object; rows nest to group
        valuefield { formula = "GetValue(\"PROFILE\")"; ... }
    }
    footer                                          // Total(...) grand totals
```

Bare `GetValue("DIAMETER")` reads the row's own object; prefixed `GetValue("ASSEMBLY.WEIGHT")`
hops to a related object. `sorttype = COMBINE` merges identical rows (counts/totals),
`DISTINCT` keeps them separate. Interior quotes in a `formula` are backslash-escaped, and
newlines inside a formula/rule string are the literal two characters `\n`.

**Write template files only with the Write/Edit tools — never through shell
echo/heredocs/`Set-Content`.** The shell adds a third escaping layer on top of the
formula's `\"` and the literal `\n`: a double-quoted Bash heredoc (or PowerShell
double-quoted string) turns `\n` into a real newline and mangles `\"`, producing a file
that parses differently from what you wrote.

**Drawing tables** (`.tpl`): every field that reads model data lives inside a `row` of the
right `contenttype` — a title block is one `row (contenttype=DRAWING)`; a revision table
nests a `REVISION` row inside a hidden `DRAWING` row. Only purely static tables use a bare
`header`. A `.tpl` can also be a full data report embedded on a drawing (cast-unit BOM,
bending schedule): it iterates model objects filtered to the host drawing with the
`CURRENT_DRAWING.` prefix. Details in `references/rows-and-content-types.md`.

## Exemplars — start from the closest one, never a blank `template` header

`assets/` ships a copy-ready skeleton per common archetype (all validate clean at grammar
v2026.0 and are TplEd-openable — one statement per line, CRLF). Pick the nearest, copy it,
adjust fields, verify attributes with the extractor. **Keep the expanded formatting — never
re-pack lines** (see the packing crash trap above).
Every skeleton — `.tpl` and `.rpt` — has a matching `.preview.svg`; SVG is the canonical
preview for both kinds (`-AsText` is an optional extra character-grid view for `.rpt`).

| Want | File | Structural trick it encodes |
|---|---|---|
| Flat part list | `skeleton_part_list.rpt` | `pageheader` + one `PART` row + `footer` `Total()` |
| Assembly + its parts | `skeleton_assembly_list.rpt` | nested `ASSEMBLY`>`PART`; hidden `MAIN_PART` sort key; per-assembly `oncombine=SUM`; hidden `WEIGHT_sum`→footer `Total()` |
| Bolt list | `skeleton_bolt_list.rpt` | hidden `ASSEMBLY`>`PART` wrapper rows for scope; hidden `DIAMETER`/`LENGTH` sort keys behind one built `"BOLT dXl"` field; `COMBINE`+`SUM` |
| Material / weight summary | `skeleton_material_summary.rpt` | `PART` `COMBINE` keyed on profile+grade; `oncombine=SUM` rolls up count & weight; footer `Total()` |
| CSV export (raw data) | `skeleton_csv_export.rpt` | `sep=;` line + literal `;` `text` between LEFT-justified fields; name the file `*.csv.rpt` |
| Formatted Excel report | `skeleton_xls_report.xls.rpt` | `text` blocks emit HTML + Excel `mso-` CSS, one `<TD>` per output line; huge `maxheight`; name the file `*.xls.rpt`. **Generate it with `New-TeklaXlsReport.ps1`, don't hand-place the blocks** |
| Title block | `skeleton_title_block.tpl` | one `row (contenttype=DRAWING)`, absolute mm, frame + `PROJECT.*`/`REVISION.LAST_*` fields |
| Revision table | `skeleton_revision_table.tpl` | hidden `DRAWING` wrapper row + nested `REVISION` row (one band/revision) |
| Drawing-embedded BOM | `skeleton_drawing_bom.tpl` | `CURRENT_DRAWING.` filter on every row; sibling sections (`PART`, `REBAR`) each heading/detail/summary; imperial branch on `XS_IMPERIAL`; footer sums each section's `Sum()` |

A shipped template in `<TeklaRoot>\Environments\common\template\` is the other good base.
**Graphical (`.tpl`) sizing is in mm** but `length` is a character count. **`justify` never
moves anything relative to its anchor**: a valuefield's box always starts at `location` x and
spans `length` character cells (≈ 0.67 × fontsize × fontratio mm each) to the RIGHT; `justify`
only aligns the value *inside* that box, and on a single-line `text` it has no visual effect
at all — `x1` is the string's left edge. To center a field in a title-block cell, put
`location` x at the cell's left edge, size `length` to the cell width, and use
`justify = CENTERED`; never place the anchor at the cell's midpoint (the field will start
there and overflow right — verified live in TplEd).

### No skeleton fits? Search the ~2,700 shipped templates

The shipped corpus is Tekla's best documentation — when the skeletons above don't cover the
archetype (a `POUR_UNIT` schedule, a rebar bending shape, a delivery ticket), find a real
template that already does it instead of reconstructing the pattern:

```powershell
scripts\Find-TeklaTemplateExamples.ps1 -ContentType REBAR -Function Sum      # REBAR rows totalled with Sum()
scripts\Find-TeklaTemplateExamples.ps1 -Feature current-drawing,footer-sum -Kind tpl
scripts\Find-TeklaTemplateExamples.ps1 -Attribute ASSEMBLY.WEIGHT -Show      # full record + on-disk path
scripts\Find-TeklaTemplateExamples.ps1 -Path CU_BOM.tpl -Content             # dump one file's record + text
scripts\Find-TeklaTemplateExamples.ps1                                       # no args = searchable facet overview
```

It queries `assets/template-index.json` (pre-built from **2026.0**: per file its content types,
formula functions, `GetValue` attributes, block types and named tricks — `nested-rows`,
`combine`, `oncombine-sum`, `footer-sum`, `hidden-rows`, `current-drawing`, `imperial-branch`,
`control-flow`, `summary-band`, `single-rebar`, `revision-table`, `drawing-table`, `csv-export`,
`xls-html`).
Axes AND together; matches rank simplest-first (`-Largest` reverses). `-Show`/`-Path` resolve the
file's real location so you can open and copy it. Regenerate for another version (~65 s,
once per version) with `scripts\Get-TeklaTemplateIndex.ps1 -TeklaRoot C:\TeklaStructures\<version>`;
`-Path` folds a firm/project library into the index, `-IndexFile` points the finder at it.
Never read `assets/template-index.json` directly — it is 1.6 MB on a single line and will flood
your context; query it only via the finder script.

## Deterministic creation — the JSON IR pipeline (the default)

**This is the preferred way to create or restructure any template.** Don't write template
text by hand when this pipeline is available: author **JSON**, gate it with a **generated
JSON Schema**, and let a fixed emitter produce the file:

```powershell
scripts\ConvertFrom-TeklaTemplate.ps1 assets\skeleton_part_list.rpt        # template -> <file>.json (lossless)
# ...edit the JSON (blocks are { block, id, props, children }; enums are plain strings,
#    TRUE/FALSE are JSON booleans, tuples are arrays, formulas are single JSON strings)...
scripts\ConvertTo-TeklaTemplate.ps1 my_list.rpt.json -Strict               # schema gate -> emit -> re-parse -> lint
```

The emitter's layout is fixed to what TplEd itself writes (CRLF, one statement per line,
`{` / `};` on their own lines, no comments), so **the three formatting crash traps above
are unreachable by construction** (the fourth — notes > 120 chars — is data, not layout:
the schema's `maxLength` rejects it at the gate), and the same JSON always emits
byte-identical text. The
schema (`assets\template-schema.json`, regenerate with `scripts\New-TeklaTemplateSchema.ps1`
after any grammar re-harvest) rejects invented block types/keys, bad enum values, wrong
tuple arities, wrong nesting, and missing always-written props *before* anything is
emitted. Proven lossless: every parseable shipped 2026.0 template round-trips
tree-identical (`tests\Test-TeklaTemplateRoundTrip.ps1` — also the regression suite
after touching parser/census/schema). It does **not** check attribute names or formula
syntax — the extractor and preview still own those. Full IR spec, value forms, and the
`{"ident"/"string": …}` escape hatch: **`references/json-ir.md`**.

## Excel reports are a separate pipeline

A *formatted* Excel report is a normal `TEXTUAL` template whose `text` blocks emit HTML +
Excel `mso-` CSS, named `*.xls.rpt` (96 shipped templates; `-Feature xls-html`). Don't
hand-author one and don't trust `-Strict` on it — the grammar check validates the *template*
and is blind to the *document* it produces:

```powershell
scripts\New-TeklaXlsReport.ps1 -Out part_list.xls.rpt -Title "Part list" -Column `
    @{ Header='Pos'; Formula='GetValue("PART_POS")' },
    @{ Header='Weight (kg)'; Formula='GetValue("WEIGHT")'; Type='Number'; Combine='SUM'; Total=$true }
scripts\Test-TeklaHtmlReport.ps1 -Path part_list.xls.rpt      # lints the emitted HTML; exit 2 on errors
```

The generator handles what silently corrupts these reports: complete cell triples, bands that
close what they open, Excel's Text format on text columns (`general` is the coercing
*default*, not a fix), `replace()` HTML-escaping of model text, and a large `maxheight`.
Two of those — `replace()` and the Text format — are documented but used by **no** shipped
template, so **verify one report in a live Tekla session** before rolling it out; `-NoEscape`
/ `-NoTextFormat` revert to shipped practice. Full treatment:
[recipes.md](references/recipes.md) → "Formatted Excel report".

## Workflows

- **Generate**: report list ⇒ `.rpt`; title block / revision table / drawing-embedded BOM ⇒
  `.tpl`. **Use the JSON IR pipeline**: `ConvertFrom-TeklaTemplate.ps1` on the closest
  exemplar gives the JSON starting point — never hand-build the `template` header from
  nothing. Verify every attribute with the extractor.
- **Edit**: for structural changes (adding/removing/moving blocks, new rows or sections),
  round-trip through the IR — convert, edit the JSON, re-emit. Direct text editing is fine
  for small in-place tweaks: copy an existing `valuefield`, adjust
  `name`/`location`/`formula`/`length`, align with header text. Change one thing at a time.
- **Preview** — always, before delivering:

  ```powershell
  scripts\Render-TeklaTemplate.ps1 -Path title_block.tpl         # -> title_block.preview.svg
  scripts\Render-TeklaTemplate.ps1 -Path part_list.rpt           # -> part_list.preview.svg (canonical for .rpt too)
  scripts\Render-TeklaTemplate.ps1 -Path part_list.rpt -AsText   # optional: character-grid mock to stdout
  scripts\Render-TeklaTemplate.ps1 -Path title_block.tpl -Strict # + grammar/comment lint
  ```

  Catches overlapping columns, fields past the width, short `length` values, table lines
  cutting through text (the y-down anchoring mistake — y anchors the text BOTTOM); warnings
  print to stderr (and into the SVG in red) — fix them, or explain why they're expected.
  Parse errors report a line number. By default fields get short realistic sample values
  and mutually-exclusive rule-guarded sibling rows collapse to one band per content type;
  `-AllVariants` stamps every variant/filter branch, `-RawValues` shows the literal
  `{ATTRIBUTE}` placeholders. Fonts are estimated — final signoff is still in Tekla.
- **Install** (a template is only visible in Tekla once it's on the template search path):

  ```powershell
  scripts\Install-TeklaTemplate.ps1 -Path part_list.rpt -ModelFolder "D:\Models\TowerA"   # per-model, highest priority
  scripts\Install-TeklaTemplate.ps1 -Path title_block.tpl -Firm -Force -Backup            # firm-wide (XS_FIRM)
  scripts\Install-TeklaTemplate.ps1 -ListTargets -ModelFolder "D:\Models\TowerA"          # show where Tekla looks
  ```

  Destination is always explicit (`-ModelFolder`, `-Destination`, `-Firm`/`-Project`);
  won't clobber without `-Force`/`-Backup`, `-WhatIf` previews. Model folder wins the
  search order, so it's best for testing.
- **Debug**: blank/truncated/`#`-filled/garbled fields — symptom→cause table in
  `references/debugging-and-workflow.md`. When inspection can't pin a fault in a multi-row
  template (crash on open, blank field, wrong total), **bisect**: rebuild from a minimal
  known-good row, adding one construct per step and previewing each, until the fault
  reappears — the "build up one row at a time" section there, with a worked `demo/bisect`
  ladder.

## References — read the one that fits

- `references/json-ir.md` — the JSON IR pipeline in full: IR shape, value forms, quoting
  decision, schema gate, round-trip proof, version regeneration. Read before authoring or
  editing templates via JSON.
- `references/recipes.md` — **goal → pattern index**: page numbering (`PAGE`/`PAGES`),
  metric/imperial branch, running counters, hidden sort keys, subtotals & grand totals,
  duplicate suppression, multilingual fields, compute-once-reuse, CSV and formatted-Excel
  (HTML-in-`.xls`) output. Start here when the user
  names an outcome rather than a language feature; each entry links the full treatment.
- `references/attribute-cookbook.md` — plain-English → attribute ("piece mark" → `ASSEMBLY_POS`),
  per-content-type most-used lists, and the attribute traps. Read when choosing attributes.
- `references/attribute-glossary.md` — what the 300 most-used attributes **mean**, in our own
  words, with type/unit/content types and corpus usage. Grep it; ~10k tokens whole.
- `references/attribute-definitions.md` — *generated locally, may be absent*: Trimble's
  definition of each documented attribute, one line each (~35k tokens). **Grep it, never read
  it whole.** The authority for what an attribute means.
- `references/file-format.md` — full block grammar, fields, coordinates, encoding.
- `references/formulas.md` — formula language: bare vs prefixed attributes, operators,
  `if…then…else…endif`, `StepOver()`, quote escaping.
- `references/functions.md` — complete function catalog + datatype/unit/precision classes.
  Read before using any function beyond `GetValue`/`Sum`.
- `references/rows-and-content-types.md` — rows, nesting, `COMBINE`/`DISTINCT`, sorting,
  `rule` filtering, hidden rows/fields.
- `references/debugging-and-workflow.md` — where templates live, search order, testing,
  debugging table.
