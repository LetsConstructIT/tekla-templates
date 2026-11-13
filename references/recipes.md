# Recipes — goal → pattern index

The other references are organized by language feature; this one is organized by what the
user asked for. Each entry gives the move, a minimal snippet, and where the full treatment
lives — nothing here is new, it's the shortest path from intent to the documented pattern
and a real shipped example. Snippets show formulas in file form (interior quotes escaped)
when they're meant to be pasted. Usage counts are from the 2026.0 shipped corpus
(`assets/template-index.json`).

## Page numbering — "Page 2 / 5"

`PAGE` (current page) and `PAGES` (total pages) are INTEGER print-metadata attributes bound
to the summary contexts (PAGEHEADER, PAGEFOOTER, HEADER, FOOTER) as well as model rows. The
shipped idiom, in a `pageheader` or `pagefooter` value field:

```
formula = "GetValue(\"PAGE\")+\"/\"+GetValue(\"PAGES\")";
```

`ROW_IN_PAGE` / `ROW_IN_ALLPAGES` number output *rows* instead of pages — shipped two-column
GA BOM tables (`STL_GA_BOM_2COLUMN_*`) use `ROW_IN_PAGE`. 134 shipped templates use `PAGES`:
`Find-TeklaTemplateExamples.ps1 -Attribute PAGES -Show`. Special sources list:
[formulas.md](formulas.md#getvalue).

## Metric/imperial dual output

Leave the field's `class`/`unit` empty and branch inline on the `XS_IMPERIAL` advanced
option (never in any attribute catalog — don't let the extractor talk you out of it):

```
if GetValue("ADVANCED_OPTION.XS_IMPERIAL") == "TRUE" then
    format(GetValue("LENGTH"), "Length", "inch-frac", 1/16)
else
    format(round(GetValue("LENGTH"), 5), "Length", "mm", 0)
endif
```

Same guard swaps unit labels (`"lb"`/`"kg"`). Full treatment under
[formulas.md](formulas.md#getvalue); working example `assets/skeleton_drawing_bom.tpl`;
shipped examples `Find-TeklaTemplateExamples.ps1 -Feature imperial-branch`. To avoid
repeating a long branch per column, see "Compute once, reuse" below.

## Running item counter — a "No." column

Shipped pattern (`TypeG_SequenceList.tpl`, USA environment; field names shortened): a hidden
key field plus `Count()` on it —

```
valuefield { name = "N";  formula = "GetValue(\"NUMBER\")"; visibility = FALSE; oncombine = SUM; ... };
valuefield { name = "No"; formula = "Count(\"N\")"; datatype = INTEGER; ... };
```

`Count("N")` prints how many `N` values have been processed — the running item number.
(The Help calls this the "intermediate count" that "resets after output" — the reset fires
when the row holding the `Count` field outputs; verified working as a running counter in
the shipped template above.) `All("field")` is the report-wide total count
("item 3 of 27"). Don't confuse with the
*quantity* column of a COMBINE row — that's the `NUMBER` **attribute** with
`oncombine = SUM` (see the `NUMBER` vs `MODEL_TOTAL` trap in
[attribute-cookbook.md](attribute-cookbook.md#2-traps)). Semantics:
[functions.md](functions.md#value-field-functions).

## Hidden sort / group key

Sorting lives on value fields (`sortdirection`), so to sort by something you don't print,
add the field anyway with `visibility = FALSE`. Multiple sorted fields sort in file order —
put hidden keys *before* the visible ones. Classic: sort by raw `DIAMETER`/`LENGTH` while
displaying one built `"BOLT d×l"` string (`assets/skeleton_bolt_list.rpt`), or group by
`MAIN_PART` (`assets/skeleton_assembly_list.rpt`). See
[rows-and-content-types.md](rows-and-content-types.md#sorting-rows) and
[hidden rows/fields](rows-and-content-types.md#hidden-rows-and-hidden-fields).

## Subtotal per group, grand total

Three tools, in increasing scope:

- **`oncombine = SUM`** on a field of a `COMBINE` row — merges identical rows and sums that
  field (quantity, weight). The per-line rollup.
- **`Sum("field")`** — resets each time the row holding it outputs ⇒ subtotal for the
  group just emitted. Put it in the parent row's band or a `SUMMARY` band.
- **`Total("field")`** — accumulates over the whole report ⇒ the footer grand total.
  Always use `Total` for grand totals: footer `Sum()` gives the same number only when the
  footer outputs once, and silently turns into a per-page/per-group subtotal otherwise.

A per-group *closing band* (subtotal line, closing frame) is a `SUMMARY` row that fires on
the last object of the group via `NextValue` — see
[rows-and-content-types.md](rows-and-content-types.md), "`SUMMARY` band". A grand total
across *sibling sections* (multi-section BOM) adds each section's `Sum(...)` explicitly in
the footer — see "Multi-section reports" in the same file. Working examples:
`assets/skeleton_part_list.rpt` (simplest: footer `Total("WEIGHT")` on the detail field),
`assets/skeleton_assembly_list.rpt` (hidden `WEIGHT_sum` → footer `Total()`),
`assets/skeleton_drawing_bom.tpl` (footer summing two sections).

## Suppress duplicates — print a value once per group

Compare the sort key against the next/previous row and skip the repeats. As a row rule
(the predefined "Assembly pos check" rule, [rows-and-content-types.md](rows-and-content-types.md#predefined-reusable-rules)):

```
rule = "if (GetValue(\"ASSEMBLY_POS\") != NextValue(\"ASSEMBLY_POS\")) then\n  Output()\nelse\n  StepOut()\nendif";
```

Variants: `StepOver()` skips just this row, `StepOut()` also abandons children; inside a
*formula*, `StepOver()` blanks the value while the row still prints. De-dup against a
summary value works the same way — e.g. skipping the newest revision already shown in the
title block (`MARK == LAST_MARK` → `StepOver()`, see
[rows-and-content-types.md](rows-and-content-types.md#drawing-list-and-revision-history-reports)).
`NextValue` appears in 230 shipped templates: `Find-TeklaTemplateExamples.ps1 -Function NextValue`.

## Multilingual / translated fields

Two different problems:

- **Follow the application language**: `TranslatedText("albl_Weight")` wrapped in
  `GetValue` — [formulas.md](formulas.md#translatedtext). Prefer it over literal strings
  for headings (203 shipped templates).
- **Follow a per-drawing / per-project language choice**: branch on a language-code UDA
  (`CURRENT_DRAWING.USERDEFINED.DR_LANGUAGE`, fallback `PROJECT.USERDEFINED.P_LANGUAGE`)
  and print the matching literal —
  [formulas.md](formulas.md#manual-multi-language-fields-uda-language-codes). Code values
  are an environment convention; read them from the environment's UDA definitions.

## Only the host drawing's objects (report embedded on a drawing)

Every section row of a drawing-placed `.tpl` report filters model objects against the
drawing's own cast unit via the `CURRENT_DRAWING.` prefix:

```
rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") then\n  Output()\nelse\n  StepOver()\nendif";
```

See [rows-and-content-types.md](rows-and-content-types.md#reports-embedded-on-a-drawing);
working example `assets/skeleton_drawing_bom.tpl`; shipped `CU_BOM.tpl`
(`Find-TeklaTemplateExamples.ps1 -Path CU_BOM.tpl -Content`).

## Compute once, reuse in many fields

Put the expensive/long formula (typically the imperial branch) in one field and read it back
elsewhere with `GetFieldFormula("field")` — returns the *formatted* value, so unit branching
carries over; multiply for derived figures (`GetFieldFormula("field_WEIGHT_1")*0.7`). Make
the source field `visibility = FALSE` if it's purely a helper. 224 shipped templates use it.
`CopyField("field")` instead pulls a value across the row hierarchy (search order: same row →
up → after → before), even from hidden rows — the way a footer reads a value computed inside
a row. [functions.md](functions.md#value-field-functions).

## Conditionally show / hide a graphic primitive

Don't duplicate a template to vary frame lines or notes — put a `visibilityrule` (same
expression language as row rules) on the individual `lineorarc`/`rectangle`/`polyline`/
`circle`. Empty = always shown. See [file-format.md](file-format.md#visibilityrule--color_argb--isalwaysvisible).

## CSV export (plain delimited)

There is no CSV output mode — you fake it: a literal `"sep=;"` `text` line first (so Excel
picks the separator), literal `;` `text` objects between LEFT-justified `DISTINCT` fields,
and a `*.csv.rpt` filename (Tekla writes the part before the last dot as the output
extension). The shipped corpus has no example of this — `assets/skeleton_csv_export.rpt`
is the reference. Use it only when the consumer wants raw data; for anything a human opens
in Excel, the HTML idiom below gives real formatting.

## Formatted Excel report — HTML inside a `.xls` file

**This is the shipped way to produce an Excel report**, and it beats CSV whenever the output
is read rather than re-imported: fonts, borders, named cell styles, column widths, page
margins, print headers and number formats all survive. **96 shipped 2026.0 templates** are
built this way — 80 `.xls.rpt`, 15 `.html.rpt` and one `.doc.rpt`, all the same idiom with a
different target application: `Find-TeklaTemplateExamples.ps1 -Feature xls-html`. (The 6
shipped `.xlsx.rpt` files are *not* this pattern — they are plain fixed-width text reports
that happen to carry an Excel extension. Don't copy those expecting formatting.)

The template itself is an ordinary `type = TEXTUAL` report — nothing in the grammar marks it.
The whole trick is that the `text` blocks contain **HTML markup and Excel's `mso-` CSS**
instead of labels, so the report Tekla writes *is* an HTML document. Name the file
`*.xls.rpt` and Tekla writes the output as `.xls`, which Excel opens as a formatted
worksheet. (It is HTML wearing an `.xls` extension, not OOXML, so Excel shows a
"file format does not match extension" prompt on open — expected, and every shipped template
has it. Suppress it per-machine with the Excel *ExtensionHardening* registry setting, or ship
`.html.rpt` if the consumer doesn't mind the extension.)

### Generate it — don't hand-place the blocks

A five-column report is ~90 blocks whose y coordinates must line up and whose tags must
pair. Author it declaratively instead:

```powershell
scripts\New-TeklaXlsReport.ps1 -Out part_list.xls.rpt -Title "Part list" -Column `
    @{ Header='Pos';         Formula='GetValue("PART_POS")' },
    @{ Header='Profile';     Formula='GetValue("PROFILE")' },
    @{ Header='Qty';         Formula='GetValue("NUMBER")'; Type='Integer'; Combine='SUM' },
    @{ Header='Weight (kg)'; Formula='GetValue("WEIGHT")'; Type='Number'; Class='Weight'; Combine='SUM'; Total=$true }
```

It emits through the JSON IR pipeline (so the TplEd crash traps stay unreachable) and
applies every hardening below by construction: complete cell triples, self-balanced bands,
the Text number format, `replace()` escaping, a large `maxheight`, and a `width` computed
from the real emitted lines. `-ContentType`, `-Sort`, `-Rule`, `-Landscape`,
`-NoProjectBlock` cover the usual variations; `-JsonOut` gives you the IR to hand-edit.

Then lint the **document**, which `-Strict` cannot see:

```powershell
scripts\Test-TeklaHtmlReport.ps1 -Path part_list.xls.rpt
```

It composes the emitted HTML exactly as Tekla will (per band, descending y, left-to-right by
x) and checks tag balance, per-band self-containment, cell counts against the heading, the
Text format, escaping, and `maxheight`. Exit 2 on errors, `-Strict` to fail on warnings too.

**One output line = one table cell.** Within a band, lines emit in **descending y** (y is a
line index from the band's bottom, so the highest y prints first — see
[file-format.md](file-format.md#coordinates-and-units)). A cell is three objects on the same y,
left to right by x:

```
text       x1 = 0    string = "<TD>"
valuefield location = (50, y)   formula = "GetValue(\"WEIGHT\")"   length = 10
text       x1 = 60   string = "&nbsp;</TD>"
```

Objects are laid out **at their x**, and the gaps between them become spaces. A tag split
across two text objects therefore gets a space in the middle — write each complete tag as one
`text` object. The field's `length` pads the value; HTML collapses that whitespace, so the
padding is free and you never fight column widths the way a fixed-pitch report makes you.
No shipped template ever concatenates markup into a `formula` — keep the tags in `text`
blocks so the field stays a plain `GetValue`.

**Band layout** — the document is split across the bands in reading order:

| Band | Emits |
|---|---|
| `header` | `<!DOCTYPE>`, `<HTML>`, `<HEAD>`, the `<style>` block, `</HEAD>`, `<BODY>`, any project/date table, and the data `<TABLE …>` opening tag |
| `pageheader` | the column-title `<TR>` of `<TD class=head>` cells |
| `row` | one `<TR>` per object, one `<TD>` per column |
| `footer` | the totals `<TR>`, then `</TABLE>`, `</BODY>`, `</HTML>` |

**The rule that makes the archetype safe: every repeating band must close what it opens.**
A `row` emits `<TR>` … `</TR>` and nothing wider; only `header` and `footer` — emitted once —
may leave the `<TABLE>`/`<BODY>`/`<HTML>` tags open across bands. Break that and the file is
fine on your desk and corrupt in production, because the damage only appears when a `rule`
filters the row out, when a section is empty, or when the report paginates. Shipped
multi-section reports (`Q_Check_Part_Names(HTML).html.rpt` and friends, 14 sibling row bands
where one opens the `<TABLE>` and another closes it) violate this and are exactly as fragile
as that implies. `Test-TeklaHtmlReport.ps1` checks it.

**Set `maxheight` very large** (shipped files use `100000`). Pagination inserts page breaks
mid-document and splits the HTML — Excel then sees a truncated table. Page breaks belong in
the CSS `@page` rule, not in Tekla's pagination.

**The `mso-` CSS is where the Excel-specific power is.** Inside `<style type="text/css">`,
wrapped in an HTML comment (`<!--` … `-->`):

- `@page { margin: …; mso-header-data: "&C&…&A"; mso-footer-data: "…Page &P"; mso-paper-source:A4; }`
  — print margins and the running header/footer, using Excel's `&`-codes.
- **`mso-number-format:"\@"` is what keeps a text column text.** `@` is Excel's Text format
  code. Without it Excel coerces on open: the piece mark `B/1-2` becomes a date, `007` loses
  its zeros, `1-2` becomes January 2nd. Apply it to **every** text column.
  **`mso-number-format:general` does not do this** — `general` *is* the coercing default.
  Of the 110 shipped HTML reports, 29 set `general`, two set it outside a `style=` attribute
  where it does nothing, and **none** use the Text format, so the shipped corpus is the wrong
  thing to copy here.
- Named classes (`.head`, `.count`, `.txt`) with `mso-style-parent:style0` give a bold heading
  row, bordered totals, a text-formatted body cell — referenced as `<TD class=head>`.
- `<TD colspan=3 style='border:none;mso-ignore:colspan'></TD>` indents a row without
  creating real merged cells.

**Escape model text going into the document.** Nothing escapes automatically, and a project
named "Smith & Sons" or a UDA containing `<` lands in the HTML raw. Wrap string columns —
`&` first, or it re-escapes its own output:

```
replace(replace(GetValue("PROFILE"), "&", "&amp;"), "<", "&lt;")
```

No shipped template does this (0 of 2,685 use `replace()` at all), so it is documented
behaviour rather than corpus-proven — **verify one report in a live Tekla session** before
rolling it out. The same caveat applies to the Text format above; `New-TeklaXlsReport.ps1`
emits both and `-NoEscape` / `-NoTextFormat` fall back to shipped practice.

Start from `assets/skeleton_xls_report.xls.rpt` (generated by the script above: project/date
block, styled heading row, `COMBINE` data row, `Total()` footer). Richer shipped references:
`Material_Excel_part_list.xls.rpt` (UK — logo `<IMG>`, `@page` header/footer, three style
classes), `TS-Material_list(EXCEL).xls.rpt` (default env), and the `310 …` / `350 …` takeoff
reports in `USA/Common/CastInPlace/Reports`.

**Previewing this archetype is different.** `Test-TeklaHtmlReport.ps1` is the real check;
`Render-TeklaTemplate.ps1 -AsText -RawValues` is the useful eyeball view, composing the lines
in output order so you can read the HTML you are about to emit. The SVG preview and the
renderer's *"does not line up under any header column"* warnings are meaningless here (the
columns are HTML cells, not character positions); the skeleton ships with five of them.
Final signoff is still opening the output in Excel.
