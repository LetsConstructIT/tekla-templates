# Rows, content types, filtering and sorting

The `row` block iterates model objects, one band per object. Nesting + `rule` + COMBINE/DISTINCT = grouped BOMs.

## The row block fields

```
row _tmp_807
{
    name        = "BOLT";
    height      = 1;
    visibility  = TRUE;         // FALSE = prints nothing but still drives iteration/grouping
    usecolumns  = TRUE;         // TRUE = participates in the template's column layout
    rule        = "";           // filter expression; "" = no filter
    contenttype = "BOLT";       // which model object this row iterates
    sorttype    = COMBINE;      // COMBINE | DISTINCT | NONE

    valuefield { ... }
    row { ... }                 // optional nested child rows
}
```

## Content types

Valid set is per Tekla version in `contenttypes.lst`; the 2026.0 set:

```
ANALYSIS_RIGID_LINK ANTIMATERIAL ASSEMBLY BOLT BUILDING BUILDING_SECTION
BUILDING_STOREY CAST_UNIT CHAMFER COMMENT CONNECTION DRAWING HIERARCHIC_CAST_UNIT
HIERARCHIC_OBJECT HISTORY HOLE LOAD LOADGROUP MESH NUT PART POUR_BREAK POUR_OBJECT
POUR_UNIT REBAR REBAR_ASSEMBLY REFERENCE_MODEL REFERENCE_OBJECT REFERENCE_ASSEMBLY
REVISION SIMILAR_ASSEMBLY SIMILAR_CAST_UNIT SIMILAR_PART SIMILAR_REBAR_ASSEMBLY
SINGLE_REBAR SINGLE_STRAND SPACE STRAND STUD SUMMARY SURFACE SURFACING TASK WASHER WELD
```

`BUILDING`/`BUILDING_SECTION`/`BUILDING_STOREY` are new in 2026.0 (absent in ≤2025).
`SUMMARY` never appears in `contenttypes.lst` for any version — it is a valid pseudo-type
(below), so don't treat its absence from the list as an error.

Two are **iteration modifiers**, not model objects:

- **`SINGLE_REBAR`** — iterates individual bars inside a REBAR group/set (`REBAR` = one row per group). Use when bars in a set differ (e.g. tapered sets, each bar dimensioned separately).
- **`SUMMARY`** — pseudo-type; one band **per enclosing group** (subtotal/closing band). Pair with a "last object in group" rule (see below).

List the exact types on the target machine:
```powershell
Get-Content "<TeklaRoot>\bin\applications\Tekla\Tools\TplEd\settings\contenttypes.lst" |
  Where-Object { $_ -and $_ -notmatch '^\s*//' }
```

`DRAWING`/`REVISION` drive drawing-table `.tpl`s **and** drawing-list/revision-history `.rpt`s (a `contenttype=DRAWING` row iterates all drawings, not just the current one). `PART`/`ASSEMBLY`/`BOLT`/`CAST_UNIT`/`REBAR` are the common report types.

## Nesting rows to group data

Copy-ready: `assets/skeleton_bolt_list.rpt` (hidden `ASSEMBLY`>`PART`>`BOLT`) and
`assets/skeleton_assembly_list.rpt` (visible `ASSEMBLY`>`PART` with per-group totals).

A nested row runs once per parent object, scoped to that parent's children. Classic bolt list — invisible ASSEMBLY/PART wrappers exist only to establish grouping scope:

```
row { name="ASSEMBLY(hidden)"; contenttype="ASSEMBLY"; visibility=FALSE; sorttype=COMBINE;
  row { name="PART(hidden)"; contenttype="PART"; visibility=FALSE; sorttype=COMBINE;
    row { name="BOLT"; contenttype="BOLT"; visibility=TRUE; sorttype=COMBINE;
        valuefield { name="STANDARD"; formula="GetValue(\"BOLT_STANDARD\")"; ... }
    }
  }
}
```

## Drawing tables: title blocks and revision tables

A value field can only read an object → **anything reading drawing/project/revision data must live inside a `row`, not a `header`.** Copy-ready: `assets/skeleton_title_block.tpl` (single `DRAWING` row) and `assets/skeleton_revision_table.tpl` (hidden `DRAWING` + nested `REVISION`). Shipped patterns:

- **Title block** (`GA_title.tpl`, `drawing_title*.tpl`): entire block (valuefields, `text` labels, `lineorarc` frame) inside **one** `row (contenttype="DRAWING")` — `GetValue("TITLE")`, `GetValue("PROJECT.NAME")`, `GetValue("SCALE1")`, `GetValue("REVISION.MARK")` resolve against the current drawing. `usecolumns = FALSE` (absolute layout), `sorttype = COMBINE`.
- **Revision table** (`GA_revision.tpl`): hidden `DRAWING` wrapper row containing a nested `REVISION` row (one band per revision: `MARK`, `TEXT1`, `TEXT2`, `DATE`).
- **Static-only** (`company_logo.tpl`, `single_note.tpl`): no model data → just a `header` with `text`/`picture`/`lineorarc`, no row.

Rule of thumb: reads model data ⇒ row of the right `contenttype`; purely static ⇒ `header`.

### The canonical revision-row rule

The nested REVISION row guards by object kind via the special `CONTENTTYPE` attribute (newlines are literal `\n`):

```
rule = "if (GetValue(\"CONTENTTYPE\") == \"REVISION\") then\n  Output()\nelse\n  StepOut()\nendif"
```

`StepOut()` = abandon this row and everything below, return to parent ("not my object, back out"). `StepOver()` = skip just the current row. Full set: [functions.md](functions.md#control-functions).

### Footer as the column header

Revisions sort newest-on-top (`sortdirection = DESCENDING` on `MARK`) and grow **upward**, so shipped revision tables put column captions in the **`footer`** as fixed-string value fields (`formula = "\"Date\""`) — a quoted constant in a formula, sharing value-field alignment (alternative to `text`).

### Drawing-list and revision-history reports

A textual `.rpt` with top-level `row (contenttype="DRAWING")` iterates **every** drawing (run from document manager): drawing register, issue log, revision history. Same `DRAWING`/`REVISION` grammar as a `.tpl`.

Two ways to reach revision data from a `DRAWING` row (both in shipped `Drawing_Revision_History.rpt`):

- **Latest-revision summary, no iteration**: `REVISION.LAST_MARK`, `REVISION.LAST_DATE_CREATE`, `REVISION.LAST_CREATED_BY`, `REVISION.LAST_DESCRIPTION`, … read the newest revision straight off the drawing. (`REVISION.LAST_*` binds to `DRAWING`/`HEADER`/`FOOTER`/`PAGEHEADER`/`PAGEFOOTER` — summary contexts.)
- **Full history**: nested `row (contenttype=REVISION)`, `MARK` sorted `DESCENDING`.

De-dup the newest revision (shown once as summary, again as first history row) — inside a `REVISION` row bare `LAST_MARK` is the drawing's newest mark:

```
rule = "if (GetValue(\"MARK\")==GetValue(\"LAST_MARK\"))\nthen \nStepOver()\nelse\nOutput()\nendif"
```

General shape: compare iterated child's value against a parent/summary value, `StepOver()` the match (vs the `CONTENTTYPE` guard, which filters by object *kind*).

### Reports embedded on a drawing

A `.tpl` can be a full data report placed on a drawing (cast-unit BOM, rebar bending schedule): iterates *model* objects (`CAST_UNIT`/`PART`/`REBAR`/`MESH`/`REBAR_ASSEMBLY`) but must show only the host drawing's objects — filter via the `CURRENT_DRAWING.` prefix (see [formulas.md](formulas.md#current_drawing--the-host-drawing-of-a-placed-tpl)). Canonical filter, on every section row of shipped `CU_BOM.tpl`:

```
rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") then\n  Output()\nelse\n  StepOver()\nendif"
```

Extra clauses narrow further: `&& GetValue(\"CLASS\") != 100 && GetValue(\"DIM_F\") > 0`. These rows use `usecolumns = FALSE`, `sorttype = COMBINE`.

#### Multi-section reports: sibling rows of different content types

Copy-ready: `assets/skeleton_drawing_bom.tpl` (two sibling sections, `CURRENT_DRAWING.` filter, imperial branch, footer grand total).

A mixed BOM is a stack of independent **top-level sibling rows**, one per object kind — not one nested hierarchy:

```
header  { text "BILL OF MATERIAL"; frame lines }
row (contenttype=CAST_UNIT)      { … nested PART rows … }
row (contenttype=REBAR)          { heading / detail / summary bands }
row (contenttype=MESH)           { … }
row (contenttype=REBAR_ASSEMBLY) { heading / detail / summary bands }
footer { grand total across all sections }
```

Each section = **three sibling rows of the same contenttype**: `*Heading` (labels), detail (one band/object), `*Summary` (`oncombine = SUM` on weight/count). Give sum fields distinct `name`s so the footer can total across sections:

```
formula = "Sum(\"field_WEIGHT\")+Sum(\"ValueField_1\")+Sum(\"ValueField_2\")+Sum(\"ValueField_7\")+Sum(\"ValueField_84\")"
```

(The report-wide equivalent of a single-list `Total(...)` footer — weights live in different rows' fields, so add their `Sum(...)`s explicitly.) Use sibling sections for mixed object types; reserve deep nesting for grouping the **same** kind.

#### `SUMMARY` band: a subtotal / closing row per group

Prints **once per group**. Fires on "last object in group": compare current group key to next object's via `NextValue`:

```
row (contenttype="SUMMARY") {
    rule = "if (GetValue(\"CAST_UNIT_POS\") != NextValue(\"CAST_UNIT_POS\")) then\n  Output()\nelse\n  StepOut()\nendif";
    lineorarc { ... }        // closing frame; or valuefields with Sum(...) for a subtotal
}
```

`StepOut()` (not `StepOver()`) on non-last objects → exactly one band where the key changes. Contrast `footer` (once per report); `SUMMARY` = per-group total in the body. Shipped rebar schedule uses it as an "end of cast unit" band drawing closing grid lines.

#### Rebar bending schedules: one detail row per shape

`Rebar Schedule.tpl` (UK GeneralConcrete): drawing-embedded report whose detail section is **dozens of sibling `REBAR`/`SINGLE_REBAR` rows, one per BS 8666 bending shape** — each shape drawn differently. Each row's `rule` selects one shape; the row carries the shape sketch as a `group` of `lineorarc`s plus dimension callouts:

```
row (contenttype="REBAR") {          // shape 00 = straight bar
    rule = "if (GetValue(\"SHAPE\") == \"00\") then Output() else StepOver() endif";
    group { lineorarc … }
    valuefield { formula = "if (GetValue(\"SHAPE\") == \"00\") then GetValue(\"LENGTH\") else GetValue(\"DIM_A\") endif"; … }
}
```

Key points:

- **`SHAPE` is a two-character string** (`"00"`, `"11"`, `"99"`), not a number. `99` = custom/no standard shape. `match(GetValue("NAME"),"*TAPERED*")` branches tapered bars to a `SINGLE_REBAR` section.
- **Leg dimensions: `DIM_A`…`DIM_R`** (`DIM_A` overall/first leg; `DIM_R` radius); each shape row shows only its shape's dimensions.
- **Coupler bars** key additionally on UDAs `CPLRSTATE_S`/`CPLRSTATE_L` (`"COUPLER"`, `"THREADED"`, `"HEADED"`, or unset) and `CPLRTYPE_S`/`CPLRTYPE_L` (`"STD"`, `"MALE"`, …), one row per combination. Test unset with `== null` (see [formulas.md](formulas.md#getvalue)).
- **Catch-all error row last**, empty `rule`, printing e.g. `"PLEASE ADD COUPLER INFO OR CHANGE PREFIX"` — flags unclassifiable bars instead of dropping them silently.

Reach for this pattern whenever one object kind must render in visually distinct variants chosen by an attribute.

### Predefined (reusable) rules

Named rules in `settings\rules.txt` next to the templates, pickable by name in the Template Editor rule dialog:

```
predefined _tmp_841
{
    name    = "Assembly pos check";
    content = "if (GetValue(\"ASSEMBLY_POS\") != NextValue(\"ASSEMBLY_POS\")) then\n  Output()\nelse\n  StepOut()\nendif";
};
```

`content` = the same rule-expression language as an inline `rule`.

## sorttype

How identical sibling rows collapse:

| sorttype | Effect |
|---|---|
| `DISTINCT` | Every object its own row (no merging). |
| `COMBINE` | Merge rows whose visible+key fields are identical; pairs with `oncombine = SUM` / count fields. |
| `NONE` | No sorting/merging by the row itself. |

"How many M20 bolts" = `COMBINE` + count/`SUM` field. Per-object detail list = `DISTINCT`.

## Sorting rows

Sorting lives on value fields, not the row: `sortdirection = ASCENDING | DESCENDING`. Multiple sorted fields sort in file order. A hidden value field (`visibility = FALSE`) is often added purely as a sort/group key (e.g. sort by `ASSEMBLY_POS` while displaying a formatted mark).

## rule: filtering

Evaluated per object; `""` = include all. In practice a non-empty rule is a conditional wrapping a **control function** — `Output()`, `StepOver()`, `StepOut()`, `StepIn()` — not a bare boolean:

```
rule = "if (IsSet(\"USERDEFINED.COMMENT\")) then\n  Output()\nelse\n  StepOver()\nendif"
```

- `Output()` = keep; `StepOver()` = drop this object; `StepOut()` = drop and stop descending into children ([functions.md](functions.md#control-functions)).
- Newlines in rules are the literal two characters `\n` — which is why template files must be written with the Write/Edit tools, never via shell echo/heredocs (a double-quoted heredoc converts `\n` to a real newline).
- Value-field functions (`Sum`, `Total`, `Count`, …) are **not** available in rules — formulas only.
- Rules otherwise use the same attribute references and operators as formulas.
- For value-dependent suppression, `StepOver()` inside a value-field `formula` works too (see `formulas.md`).

Rule of thumb: `rule` = "which objects belong in this report at all" (structural, e.g. only site bolts); `StepOver()` in a formula = "sometimes print nothing for this object" (value-dependent). Diff shipped `B_Bolt_List_Site_Only.rpt` vs `B_Bolt_List_Shop_Only.rpt` for the canonical `rule` example.

## Hidden rows and hidden fields

- **Hidden row** (`visibility = FALSE`): still iterates and groups; grouping scaffolding (ASSEMBLY/PART wrappers above).
- **Hidden field**: still computed; sort/group keys or inputs to `Sum(...)`/`value(...)` in another field.

Report "missing" totals or grouping ⇒ check the hidden scaffolding rows/fields exist.
