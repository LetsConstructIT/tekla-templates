# Tekla template file format (.rpt / .tpl)

`.rpt` (textual reports) and `.tpl` (graphical drawing tables) share the **same grammar**.
Only differences: `type = TEXTUAL` vs `GRAPHICAL`, and which object blocks are typical.
Both are editable directly as text.

## Top-level structure

One `template { ... }` block containing a header, then section blocks
(`pageheader` / `header` / `row` / `footer`) holding content objects
(`text`, `valuefield`, `lineorarc`, `picture`; graphical also `rectangle`, `group`,
`graphicalfield`) and/or nested rows.

```
template
{
    name = "template_1";
    type = TEXTUAL;          // or GRAPHICAL
    ... header fields ...

    pageheader { ... }       // once per page (textual)
    header      { ... }      // once, top of table
    row  _tmp_0 { ... }      // repeats per model object; can nest
    footer      { ... }      // once, bottom
}
```

Optional identifier after the keyword (`row _tmp_807 { ... }`): Tekla auto-generates
`_tmp_NNNN`; only uniqueness within the file matters. Hand-authored files may omit ids or
use readable ones — nothing references them.

## The `template` header block

```
name        = "template_485";
type        = TEXTUAL;              // TEXTUAL (reports) | GRAPHICAL (drawing tables)
width       = 78;                   // in template grid units
maxheight   = 120;
columns     = (1, 1);               // (1,1) = single column
gap         = 1;
fillpolicy  = EVEN;
filldirection = HORIZONTAL;         // HORIZONTAL | VERTICAL
fillstartfrom = TOPLEFT;            // graphical only
margins     = (4, 0, 0, 0);         // (top, bottom, left, right)
gridxspacing = 1;
gridyspacing = 1;
version     = 3.21;                 // format version — LEAVE AS-IS when editing
created     = "29.10.2004 12:02";
modified    = "10.08.2021 15:16";
notes       = "…";                  // MAX 120 chars — longer crashes TplEd on open
colors      = "153;152;…";          // graphical only: palette for color= indices
```

New template: copy a header from `assets/`, adjust `type`/`width`/`margins`/`name`.
Never bump `version` — it controls parsing; wrong value can make the template fail to open.
`notes` is a fixed 120-char buffer in Template Editor — a longer value crashes it on open
(the `-Strict` lint flags this). Don't use it for embedded documentation; keep it a one-liner.

## Section blocks

Output order: pageheader → header → rows → footer. All optional.

| Block | Purpose | Repeats? |
|---|---|---|
| `pageheader` | Column titles / banner per printed page (textual). | Once per page |
| `header` | Fixed top content (title-block outline, logo, headings). | Once |
| `row` | Data band — iterates model objects of its `contenttype`; nests to group. | Per object |
| `pagefooter` | Per-page bottom banner; carries `outputpolicy`/`pagefrom`. | Once per page |
| `footer` | Totals / summary. | Once |

Every block has `name` and `height`. Rows carry data binding (`contenttype`, `rule`,
`sorttype`, `visibility`, `usecolumns`) — see `rows-and-content-types.md`.

```
pageheader
{
    name = "PAGEHEADER";
    height = 10;
    outputpolicy = NONE;      // NONE | ODD | EVEN
    text { ... }
    valuefield { ... }
}
```

## Content objects

### `text` — static string

```
text
{
    name = "text_534";
    x1 = 16; y1 = 1; x2 = 16; y2 = 1;
    string = "Assembly list";
    fontname = "Courier New";
    fontcolor = 153;                    // palette index
    fonttype = 2;
    fontsize = 0.8;                     // glyph HEIGHT — units depend on template type, see below
    fontratio = 0.75;                   // width/height
    fontslant = 0;
    fontstyle = 0;                      // bitmask bold/italic/underline
    angle = 0;
    justify = LEFT;                     // LEFT | CENTERED | RIGHT — no visual effect on a
                                        // single-line text: x1 is ALWAYS the left edge
    pen = 0;
}
```

**`x1` is the string's left edge regardless of `justify`.** Template Editor never
re-anchors a text on its point — `justify = CENTERED` does *not* center the string on
`x1` (verified live in TplEd 2026). To center a caption over a cell, compute the left
edge yourself (`x1 ≈ cell_center − 0.5 × string_width`), or better, use an invisible-pen
`valuefield` with a literal formula and `justify = CENTERED` over the cell width.

**`fontsize` units** (same rule for `text` and `valuefield`): the value is the glyph
*height* in the template's own coordinate units — **mm** in a graphical template
(inches under imperial preferences), **character rows** in a textual one. Two
consequences:

- **Textual `.rpt`**: font settings are Template Editor display styling only — the
  output is plain text, so `fontsize` never affects the report (TplEd Help: "In textual
  templates the font settings are used only in Template Editor, not in the output
  template"). Copy `fontsize = 0.8` from the skeletons (just under one row, so preview
  text sits inside a 1-row band) and move on; actual layout is controlled by `length`
  (characters) and row `height` (rows).
- **Graphical `.tpl`**: `fontsize` is real text height in mm on the drawing sheet.
  Pick it like drawing text height — 2.0–2.5 mm for table content, 3–5 mm for
  titles/headings — and keep it smaller than the row `height` (also mm), or the glyphs
  overrun the band (the preview's "cuts through" warning,
  see [debugging-and-workflow.md](debugging-and-workflow.md)).

### `valuefield` — value computed from the model

```
valuefield
{
    name = "WEIGHT";
    location = (65, 0);
    formula = "GetValue(\"WEIGHT\")";   // see formulas.md
    datatype = STRING;                  // STRING | DOUBLE | INTEGER
    class = "";
    cacheable = TRUE;
    justify = CENTERED;
    visibility = TRUE;                  // FALSE = compute but don't print (sort/group keys)
    angle = 0;
    length = 8;                         // width in characters — too small ⇒ truncation (common bug)
    decimals = 1;
    unit = "kg";
    maxnumoflines = 1;                  // 1 = never wrap, truncate
    formatzeroasempty = FALSE;          // TRUE = 0/empty prints blank
    aligncontenttotop = FALSE;
    sortdirection = NONE;               // NONE | ASCENDING | DESCENDING
    oncombine = NONE;                   // NONE | SUM | ... on COMBINE
    fontname = "Arial";
    fontcolor = 153; fonttype = 2; fontsize = 2; fontratio = 1;   // fontsize 2 = 2 mm (graphical); use 0.8 in .rpt
    fontstyle = 0; fontslant = 0; pen = 0; fontlinewidth = 1;
}
```

Key fields: `formula`, `datatype` (affects sorting/`oncombine`), `visibility` (FALSE for
hidden keys), `sortdirection`, `oncombine` (`SUM` totals combined rows), `length`.

**Geometry: the field box starts at `location` x and spans `length` character cells to
the RIGHT** (one cell ≈ `0.67 × fontsize × fontratio` mm in a graphical template).
`justify` aligns the value *inside* that fixed box — it never moves the box. So
`justify = CENTERED` with `location` at a cell's midpoint does NOT center the field on
that point; it plants the box's left edge there and the field overflows right. To center
a value in a title-block cell: `location` x = cell left edge (+ padding), `length` ≈
cell_width_mm ÷ (0.67 × fontsize × fontratio), `justify = CENTERED`. RIGHT-justify makes the value end at
`location.x + length × cellwidth` (see the shipped `Mark/embed.tpl` "d x l" tiling).

**`class` + `unit` + `datatype` are a set** for formatted numbers/dates — declarative
equivalent of `format(...)` (see [formulas.md](formulas.md),
[functions.md](functions.md#datatypes-units-precisions)):
- weight: `datatype = DOUBLE; class = "Weight"; unit = "kg"; decimals = 1`
- date: `datatype = INTEGER; class = "Date"; unit = "dd.mm.yyyy"` (dates are integers rendered by class/unit)
- `class = ""` = raw value, no unit conversion. Classes: `Weight`, `Length`, `Area`, `Volume`, `Date`, …

Debugging traps (see [debugging-and-workflow.md](debugging-and-workflow.md)):
`maxnumoflines = 1` silently truncates; `formatzeroasempty = TRUE` blanks a legitimate `0`.
`pen = -1` = no visible pen/box; `pen = 0` = default pen.

### `lineorarc` — line or arc

```
lineorarc
{
    name = "LineOrArc";
    x1 = 0; y1 = 0; x2 = 160; y2 = 0;
    pen = 0; color = 153; linetype = 1; linewidth = 2;
    bulge = 0;                          // 0 = straight; nonzero = arc
}
```

### `picture` — embedded image (logos)

Graphical templates. References image **by filename** on the symbol/bitmap search path
(e.g. `...\common\symbols\`), not embedded bytes:

```
picture _tmp_30248
{
    name = "Picture";
    file = "Tekla-Powered-by-logo-high.png";
    refpoint = (121, 29.9);             // bottom-left anchor
    height = 20.03;
    width = 38.96;
    keepaspect = TRUE;                  // don't distort
}
```

A pure-logo table (shipped `company_logo.tpl`) = one `picture` in a `header`. Copy a real
block and swap `file`/`refpoint`/size.

### `rectangle` — box (borders, filled cells)

```
rectangle _tmp_908
{
    name = "Rectangle";
    x1 = 81; y1 = 23; x2 = 200; y2 = 52;   // opposite corners
    filled = FALSE;                         // TRUE = solid fill
    filltype = -1;                          // fill pattern index
    pen = -1; color = 153; linetype = 1; linewidth = 1;
}
```

One unfilled `rectangle` replaces several `lineorarc`s — prefer it for cell borders /
table grids (rebar schedules use dozens).

### `group` — named bundle of graphic primitives

Collects `lineorarc`/`rectangle`/`text` so they move/hide as a unit (Template Editor
"Group"). How reusable diagrams are packaged — e.g. a rebar bending-shape sketch in the
row matching that shape code:

```
row (contenttype="REBAR") {
    group _tmp_19545 {
        name = "Group_6";
        lineorarc { ... }
        lineorarc { ... }
    }
    valuefield { formula = "GetValue(\"DIM_A\")"; ... }
}
```

Group has only `name` + children — no `contenttype` or own coordinates; children keep
their own `x1/y1`. Edit them exactly as loose primitives.

### `graphicalfield` — model-generated graphic

Tekla renders a graphic **from the model object** — notably `PULLOUT` (true bent-bar
diagram of the current REBAR/SINGLE_REBAR). Anchored like a `valuefield`
(`location` + `height`/`width`); font/style via `userattribute` sub-blocks:

```
graphicalfield _tmp_10427
{
    name = "GraphicalField";
    location = (108, 2);
    field = "PULLOUT";                  // also DIM_R_ALL, CONTENTTYPE, …
    height = 22; width = 67;
    userattribute { name = "FontName";  value = "ArialNarrow"; };
    userattribute { name = "FontColor"; value = "1"; };
}
```

Rebar schedules use **both**: `group` sketch for the generic shape, `PULLOUT`
`graphicalfield` for true per-bar geometry. Confirm supported `field=` values for the
target version; copy the `userattribute` list from a working block.

Fields may also carry **`applicationattribute`** sub-blocks — typed `name`/`type`/`value`
triples (e.g. `name = "AutoFontSizeStep"; type = DOUBLE; value = 0.5`). Copy a working
one; don't invent names.

### `polyline` and `circle`

Common in drawing-side title blocks/diagrams (Finnish environment: ~370 `polyline`s).
`polyline` = **container of child `lineorarc` segments** treated as one closed, fillable
shape (geometry lives in the children, not a points list). `circle` = ring or disc.

```
polyline _tmp_7036
{
    name = "Polyline_4";
    filled = TRUE;
    filltype = 1;                      // -1 = none
    color = 153; linetype = 1; linewidth = 1; pen = -1;

    lineorarc _tmp_7037 { x1 = 41; y1 = 1; x2 = 41.94; y2 = 3.20; bulge = 0; ... };
    lineorarc _tmp_7038 { ... };       // one per edge; bulge != 0 = arc
}

circle _tmp_1286
{
    name = "Circle_i57_1";
    center = (17.91, 14.13); radius = 5.09;
    filled = FALSE; filltype = -1;
    pen = -1; color = 161;
    color_argb = "#ff00ff00";          // ARGB hex, or -1 = use palette color
    linetype = 1; linewidth = 1;
    isalwaysvisible = TRUE;
    visibilityrule = "";
}
```

`symbol` (glyph from `.sym`) is genuinely rare — treat like `picture`: copy a working block.

### `visibilityrule` / `color_argb` / `isalwaysvisible`

On every modern graphic primitive (`lineorarc`, `rectangle`, `polyline`, `circle`);
absent from older 3.x field lists:

- **`visibilityrule`** — rule-expression string (same language as row `rule`, see
  [rows-and-content-types.md](rows-and-content-types.md#rule-filtering)) evaluated per
  object; shows/hides *that single primitive*. Empty = always shown. Use instead of
  duplicate templates for conditional frame lines/notes.
- **`color_argb`** — true-color ARGB hex (`"#ff00ff00"`); `-1` = use palette `color` index.
- **`isalwaysvisible`** — `TRUE` = visible regardless of visibility rule / layer state.

## Coordinates and units

- Grid units: ~mm for graphical, character cells for textual. `text` uses `x1,y1,x2,y2`;
  `valuefield` uses `location = (x, y)`.
- **Y axis points UP — origin bottom-left — for BOTH `.tpl` and `.rpt`.** Within a block,
  `y = height` is the top edge, `y = 0` the bottom; the upper element gets the *larger* y.
  Authoring as if y grew downward produces vertically mirrored output (title at bottom of
  header, labels under values).
  - Graphical (`.tpl`): single-band title block uses absolute y — top row near
    `maxheight`, bottom row near `0`.
  - Textual (`.rpt`): y = line index within a band, from the bottom — in a `pageheader`
    the title gets the highest y, column headings the lowest. Verified against shipped
    templates. Only affects position *within a band*; overall output still flows top-down
    by section/row order, independent of y.
- Textual alignment is column-based: give value fields the same x as their `pageheader`
  title so data lines up under headings.

## Encoding and syntax rules

- Statements end with `;`. Nested blocks close with `};` — **including the top-level
  `template { ... }` block itself**. Missing final `;` ⇒
  `ERROR: line N -> Missing ';'` at the last line.
- Strings double-quoted; quotes inside `formula` are backslash-escaped:
  `formula = "GetValue(\"PROFILE\")";`.
- **No structural comments.** `//` or `/* */` between blocks/properties makes TplEd
  **crash on open** (silent stack overflow, no dialog). `//` is legal **only inside a
  quoted `formula`/`rule` string** (~5 shipped templates use it, all in formulas). Beware:
  the skill's parser (`_TemplateParser.ps1`) *strips* comments, so such a file parses and
  previews cleanly while still crashing TplEd — `-Strict` runs a raw-text lint that
  catches this (`Test-TeklaTemplates.ps1` buckets these as `tpled-incompat`). Always run
  `-Strict` before delivering.
- **One statement per line; `{` and `}` each on their own line.** This is a hard TplEd
  requirement, not a style preference: packing two `name = value;` assignments onto one
  physical line, or opening a block inline (`text { name = "x"; … };`), makes TplEd
  **crash on open** (silent stack overflow, exception `0xc0000409`, no dialog). Verified
  live — an expanded file opens, the byte-identical packed file crashes — and by the
  corpus: **none of the 2,689 shipped 2026.0 templates has a single packed line.** The
  skill's parser is whitespace-insensitive, so a packed file previews cleanly while
  crashing TplEd; `-Strict` flags packing (bucketed `tpled-incompat`). Extra spaces *within*
  a line are fine; it's the second statement/inline `{` on a line that kills it.
- **Windows (CRLF) line endings.** TplEd's parser assumes CRLF and crashes (same
  `0xc0000409`) on bare-LF files; every shipped template is CRLF. The Write/Edit tools emit
  LF — `Install-TeklaTemplate.ps1` normalizes to CRLF on install, and `-Strict` flags
  bare-LF. Note CRLF-normalization does **not** fix packing; the two are independent traps.
- Save in the environment's encoding (typically ANSI/UTF-8 without BOM for legacy
  templates). Non-ASCII garbage ⇒ encoding mismatch — see `debugging-and-workflow.md`.
- Safest new-template path: start from a real one
  (`<TeklaRoot>\Environments\...\template\` or `assets/`) — header/`version`/font blocks
  are fiddly from scratch.
- **The block/key vocabulary is closed and checkable**: legal block types, property keys,
  and enum values are enumerated in `assets/template-grammar.json` (harvested from ~2,700
  shipped templates by `scripts\Get-TeklaGrammar.ps1`). Run
  `scripts\Render-TeklaTemplate.ps1 -Strict` to flag invented words — Tekla otherwise
  ignores unknown keys silently.
