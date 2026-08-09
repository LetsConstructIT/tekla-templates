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

## CSV / Excel export

There is no CSV output mode — you fake it: a literal `"sep=;"` `text` line first (so Excel
picks the separator), literal `;` `text` objects between LEFT-justified `DISTINCT` fields,
and a `*.csv.rpt` filename (Tekla writes the part before the last dot as the output
extension). The shipped corpus has no example of this — `assets/skeleton_csv_export.rpt`
is the reference.
