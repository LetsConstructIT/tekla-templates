# Attribute cookbook — plain English → attribute

`Get-TeklaAttributes.ps1` answers *"is `WEIGHT_NET` real, and what's its datatype?"*. It cannot
answer *"the user said **piece mark** — what do I type?"*. This file covers that gap: the
naming a fabricator uses, mapped to the attribute Tekla actually exposes, plus the traps where
a plausible guess silently produces the wrong number.

Facts here (names, datatypes, units, which content type binds what) were extracted from
**Tekla 2026.0**'s `contentattributes_global.lst`; the "most-used" rankings are real usage
counts across the **2,686 shipped templates** in `assets/template-index.json`, not opinion.
Attribute *availability* varies by version and environment — this file orients you, and
`Get-TeklaAttributes.ps1` is still the authority for a specific install:

```powershell
scripts\Get-TeklaAttributes.ps1 -ContentType PART -Name '^WEIGHT'
```

**For what an attribute *means*, grep `references/attribute-definitions.md`** when it exists.
It's generated locally from Trimble's "Template attributes" PDF (see SKILL.md, Step 1) and is
the authority on meaning; this cookbook is about choosing names and avoiding traps.

Descriptions and gotchas below are hand-written, and have to be. Tekla's own `.ail` description
file can't source them: of its 901 entries, **633 just restate the attribute name** — and that's
precisely where the common ones land (`WEIGHT` → "Weight", `PROFILE` → "Profile", `MATERIAL` →
"Material", `WEIGHT_GROSS` → "Gross Weight"). The remaining 268 are thin one-liners
(`ASSEMBLY_POS` → "Assembly position number"). None of them record which content type binds the
attribute, or any of the traps in §2 — which is the part that actually costs time.

## 1. Say it in English

| The user says | Attribute | On | Notes |
|---|---|---|---|
| piece mark, assembly mark, shipping mark | `ASSEMBLY_POS` | PART, ASSEMBLY | CHARACTER, not a number — `"B-12A"` sorts as text |
| part mark, single-part mark | `PART_POS` | PART | The piece *inside* the assembly |
| cast unit mark, precast mark | `CAST_UNIT_POS` | PART, CAST_UNIT, REBAR | |
| bar mark, rebar mark | `REBAR_POS` | REBAR | |
| grade, steel grade, material grade (**steel/concrete part**) | `MATERIAL` | PART, CAST_UNIT | **Not `GRADE`** — PART does not bind `GRADE`. `"S355J2"`, `"C30/37"` |
| grade (**bolt, rebar, mesh, stud**) | `GRADE` | BOLT, REBAR, MESH, STRAND, STUD, WASHER | These bind `GRADE` and *not* `MATERIAL` in the part sense |
| material type, steel vs concrete | `MATERIAL_TYPE` | PART, ASSEMBLY, CAST_UNIT | `"STEEL"` / `"CONCRETE"` — the standard imperial/branching test |
| profile, section, size (**part**) | `PROFILE` | PART | `"HEA300"`, `"PL10*200"` |
| size (**rebar/mesh**) | `SIZE` | REBAR, MESH, STRAND | Bar diameter as text, e.g. `"16"` |
| bar diameter (**bolt**) | `DIAMETER` | BOLT | FLOAT mm — bolts use `DIAMETER`, rebar uses `SIZE` |
| name | `NAME` | PART, BOLT, REBAR, DRAWING | User-set part name (`"BEAM"`), not the profile |
| assembly name | `ASSEMBLY_NAME` | ASSEMBLY | **`NAME` is not bound to ASSEMBLY** — see §2 |
| weight, unit weight | `WEIGHT` | PART, ASSEMBLY, CAST_UNIT, BOLT, REBAR | FLOAT kg — see the weight trap in §2 |
| net weight | `WEIGHT_NET` | PART, ASSEMBLY, CAST_UNIT | |
| gross weight | `WEIGHT_GROSS` | PART, ASSEMBLY, CAST_UNIT | |
| total weight of a rebar group | `WEIGHT_TOTAL` | **REBAR, MESH, STRAND only** | Not on PART/ASSEMBLY — see §2 |
| weight per metre (**part**) | `PROFILE.WEIGHT_PER_UNIT_LENGTH` | PART | kg/m — via the `PROFILE.` prefix; bare `WEIGHT_PER_UNIT_LENGTH` is **not** bound to PART |
| weight per metre (**rebar**) | `WEIGHT_PER_UNIT_LENGTH` | REBAR, SINGLE_REBAR | kg/m |
| length | `LENGTH` | PART, ASSEMBLY, BOLT, REBAR | FLOAT mm |
| width / height | `WIDTH` / `HEIGHT` | PART, ASSEMBLY, CAST_UNIT | FLOAT mm |
| area, painting area | `AREA` | PART, ASSEMBLY, CAST_UNIT | FLOAT m² |
| volume | `VOLUME` | PART, CAST_UNIT | FLOAT m³ |
| finish, paint, coating, galvanising | `FINISH` | PART, BOLT, STUD | CHARACTER, free text from part properties |
| class | `CLASS_ATTR` | PART, MESH, REBAR, SURFACE | **Not `CLASS`** — see §2 |
| class (**rebar/mesh/strand**) | `CLASS` | REBAR, MESH, STRAND | The one place bare `CLASS` is right (REBAR binds both) |
| phase | `PHASE` | PART, ASSEMBLY, CAST_UNIT, BOLT, … | INTEGER — the phase *number*. `PHASE.NAME` for its text, `PHASE.COMMENT` for the note |
| lot, delivery lot, shipment | `LOT_NUMBER` / `LOT_NAME` | ASSEMBLY, CAST_UNIT | INTEGER / CHARACTER. Not on PART |
| how many of these are there | `NUMBER` | any model object | INTEGER, respects `COMBINE` — see §2 |
| how many in the whole model | `MODEL_TOTAL` | any model object | INTEGER, ignores filters — see §2 |
| project number | `PROJECT.NUMBER` | any | **CHARACTER, not INTEGER** — see §2 |
| drawn by / checked by | `USERDEFINED.DR_DRAWN_BY` / `USERDEFINED.DR_CHECKED_BY` | DRAWING | UDA — needs `-IncludeUserDefined` to verify, see §3 |
| any UDA / custom property | `USERDEFINED.<name>` | varies | Defined in `objects.inp`, not the global catalog — see §3 |
| weld seam length (start → end) | `WELD_ACTUAL_LENGTH1` / `…2` | WELD | FLOAT mm, above / below line. **Includes the gaps** of an intermittent weld — see §2 |
| intermittent segment length | `WELD_LENGTH1` / `…2` | WELD | The *Length* box in weld properties, not the seam length |
| intermittent pitch | `WELD_PERIOD1` / `…2` | WELD | The *Pitch* box. FLOAT, no unit class in the catalog |
| continuous vs intermittent | `WELD_INTERMITTENT_TYPE` | WELD | CHARACTER: Continuous / Chain / Staggered intermittent |
| weld volume (→ weld metal weight) | `WELD_VOLUME` | WELD | mm³ of the solid weld; **0 for unsupported weld types or a failed solid** |
| project name / client / designer | `PROJECT.NAME` / `PROJECT.BUILDER` / `PROJECT.DESIGNER` | any | |
| drawing title | `TITLE` (DRAWING) or `TITLE1`..`TITLE3` | DRAWING | `TITLE1-3` are the free title lines on most objects |
| drawing date / date created | `DATE_CREATE`, `DATE_ISSUE` | DRAWING | INTEGER + `class = "Date"` — see §2 |
| revision mark / latest revision | `REVISION.MARK` / `REVISION.LAST_MARK` | DRAWING | |
| scale | `SCALE1`..`SCALE3` | DRAWING | |
| bolt standard | `BOLT_STANDARD` | BOLT | `"7990"`, `"A325"` |
| site or shop bolt | `SITE_WORKSHOP` | BOLT | The site/shop split every bolt list needs |
| bending shape | `SHAPE` | REBAR | |
| bending dimensions | `DIM_A`..`DIM_J`, `DIM_R` | REBAR | FLOAT mm, per bending shape |
| main part of an assembly | `MAINPART.<attr>` | ASSEMBLY, CAST_UNIT, DRAWING | `MAINPART.PROFILE`, `MAINPART.NAME` … |
| GUID / unique id | `GUID` | any | Stable across sessions; `ID` is **not** |
| imperial or metric | `ADVANCED_OPTION.XS_IMPERIAL` | any | `== "TRUE"` — the standard unit branch |

## 2. Traps

**`GRADE` is not a part's grade.** `PART` doesn't bind `GRADE` at all — a part's grade lives in
`MATERIAL`. `GRADE` belongs to bolts, rebar, mesh, strands, studs and washers. `GetValue("GRADE")`
in a `PART` row yields nothing, silently.

**`CLASS` vs `CLASS_ATTR`.** `PART` binds `CLASS_ATTR`, *not* `CLASS`; bare `CLASS` is bound only
to REBAR/MESH/STRAND. This bites because `CLASS` looks obviously right and fails quietly. The
shipped corpus reflects the split exactly: `MAINPART.CLASS_ATTR` (64 templates) for parts,
`REBAR.CLASS` for rebar.

**An assembly has no `NAME`.** `NAME` is bound to PART, BOLT, REBAR, DRAWING and ~24 others — but
*not* ASSEMBLY. An assembly's name is `ASSEMBLY_NAME`. `GetValue("NAME")` in an `ASSEMBLY` row is
blank; reach the main part's name with `MAINPART.NAME` if that's what you meant (which it usually
is — `MAINPART.NAME` appears in 236 shipped templates against `ASSEMBLY_NAME`'s 79).

**`NUMBER` vs `MODEL_TOTAL`.** `NUMBER` is the count for the row's *own* object (per source
line — it does **not** self-adjust under `COMBINE`); `MODEL_TOTAL` is the count of similar
objects in the whole model, ignoring your filters. A filtered list ("phase 2 only") that
reports `MODEL_TOTAL` shows counts from the entire model — a wrong BOM that looks plausible.
Want the count in *this* report? `NUMBER` with `oncombine = SUM` on the `COMBINE` row — the
canonical quantity column (TplEd Help: "to print the number of combined output lines, add a
value field with the attribute NUMBER"; 62 of 66 `NUMBER` fields in shipped system reports
pair it with `oncombine = SUM`). With `oncombine = NONE`, `COMBINE` outputs only the *last*
merged line's value — the QTY column undercounts.

**`PROJECT.NUMBER` is CHARACTER, `NUMBER` is INTEGER.** Same name, two datatypes. Real project
numbers (`"2024-A"`) are strings; setting `datatype = INTEGER` on that field truncates or blanks
it. The catalog encodes this as `NUMBER#1` (INTEGER, ~25 model content types) and `NUMBER#2`
(CHARACTER, `PROJECT` only). **You never type the `#N`** — Tekla resolves it from the prefix, and
it appears in 0 of the 2,686 shipped templates. `Get-TeklaAttributes.ps1` strips it for you.

**`WEIGHT_TOTAL` is not "the total weight".** It's bound only to REBAR/MESH/STRAND, where it means
the whole bar group (`WEIGHT` being one bar). There is no `WEIGHT_TOTAL` on PART or ASSEMBLY —
total a part list in the `footer` with `Total()`, as the skeletons do.

**Three weights, all kg.** `WEIGHT`, `WEIGHT_NET` and `WEIGHT_GROSS` are distinct values — Tekla's
own inquiry report prints all three on separate lines. `WEIGHT_GROSS` is the undeducted figure and
`WEIGHT_NET` deducts cuts and holes; **which one bare `WEIGHT` equals is not documented in the
install and differs by object type** — on rebar, shipped templates label `GetValue("WEIGHT")` as
the gross column. If the distinction matters for a delivery ticket, verify against one known part
in the actual model rather than trusting any of the three by name.

**Dates are INTEGER with `class = "Date"`.** `DATE`, `DATE_CREATE`, `DATE_ISSUE` are INTEGER in the
catalog with unit `dd.mm.yyyy`; shipped title blocks declare `datatype = INTEGER; class = "Date";`
and let the class format them. There is no `DATE` datatype — `class` drives the rendering.

**`ID` is not stable, `GUID` is.** `ID` (the running number) changes; use `GUID` to key anything
that must survive a re-open or round-trip.

**No attribute gives the deposited length of an intermittent weld.** `WELD_ACTUAL_LENGTH1/2`
is the seam length from start point to end point, gaps included (Trimble's definition, §21.21
of the 2025/2026 PDFs). Tekla's own weld inquiry report labels it "Actual length", which is
what misled a user's report into totalling 500 mm for a 500 mm, 100-on/100-off weld that has
300 mm of metal. Derive it from the seam length, the segment length (`WELD_LENGTH1`) and the
pitch (`WELD_PERIOD1`). How many segments fit depends on two things the documentation doesn't
settle: whether *Pitch* is centre-to-centre or the gap, and how Tekla places the end segments.
One user's field-checked formula, with segment length `s` and gap `g`, was
`(ceil((L − s) / (g + s)) + 1) × s`. Confirm it against one weld in the actual model (Inquire)
before the report goes to the workshop, and do the same for the below-line side and for
staggered welds.

**`LOT_NUMBER` is assembly-level.** ASSEMBLY and CAST_UNIT only — a `PART` row can't read it
directly; go through the assembly.

## 3. When the extractor says "No attributes matched"

That warning normally means you invented a name. For three prefixes it doesn't — they resolve at
runtime and are not in `contentattributes_global.lst`, so a default extractor run denies attributes
that are correct and common. Don't reject these on the extractor's say-so:

| Prefix | In global catalog | Real usage | How to verify |
|---|---|---|---|
| `USERDEFINED.<uda>` | no (1 stray entry) | **646 of 2,686 templates** | Re-run with `-IncludeUserDefined`; it reads `contentattributes_userdefined.lst` |
| `ADVANCED_OPTION.XS_*` | **0 entries** | 353 templates | Never in any catalog. Verify the option name in Tekla's advanced-options list instead |
| `TranslatedText("albl_*")` | 0 entries | 203 templates | A function call, not an attribute — see `references/functions.md` |

Worked example — `USERDEFINED.DR_DRAWN_BY` is used in 91 shipped templates, yet:

```powershell
scripts\Get-TeklaAttributes.ps1 -Name 'DR_DRAWN_BY'
# WARNING: No attributes matched.        <- looks invented, isn't
scripts\Get-TeklaAttributes.ps1 -Name 'DR_DRAWN_BY' -IncludeUserDefined
# DRAWING   USERDEFINED.DR_DRAWN_BY   CHARACTER
```

UDAs ultimately come from the environment's `objects.inp`, so a firm- or project-specific UDA can
be absent even with `-IncludeUserDefined` and still be perfectly valid in that model. Confirm
against the project rather than deleting the field. Most-referenced UDAs in the shipped corpus:
`DR_DRAWN_BY`, `DR_CHECKED_BY`, `BOUGHT_ITEM`, `GAGE`, `comment`. UDA names are **case-sensitive**:
`USERDEFINED.COMMENT` and `USERDEFINED.comment` are two different attributes, both shipped, and
picking the wrong case yields a blank field.

## 4. Most-used attributes, by content type

Ranked by how many of the 2,686 shipped templates use each in a row of that content type — a good
proxy for what a real report needs. `MAINPART.*` prefixed forms are shown where they outrank the
bare one.

### PART
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `LENGTH` | FLOAT | mm | | `WEIGHT_NET` | FLOAT | kg |
| `PROFILE` | CHARACTER | | | `MATERIAL_TYPE` | CHARACTER | |
| `NAME` | CHARACTER | | | `CAST_UNIT_POS` | CHARACTER | |
| `MATERIAL` | CHARACTER | | | `HEIGHT` | FLOAT | mm |
| `DATE` | INTEGER | dd.mm.yyyy | | `MAIN_PART` | INTEGER | |
| `PART_POS` | CHARACTER | | | `MAINPART.PROFILE` | CHARACTER | |
| `ASSEMBLY_POS` | CHARACTER | | | `ID` | INTEGER | |
| `WEIGHT` | FLOAT | kg | | `VOLUME` | FLOAT | m3 |
| `PROJECT.NAME` | CHARACTER | | | `PROFILE_TYPE` | CHARACTER | |
| `PAGE` | INTEGER | | | `MAINPART.MATERIAL` | CHARACTER | |
| `MODEL_TOTAL` | INTEGER | | | `FINISH` | CHARACTER | |
| `WIDTH` | FLOAT | mm | | `PHASE` | INTEGER | |
| `AREA` | FLOAT | m2 | | `CLASS_ATTR` | CHARACTER | |
| `MAINPART.NAME` | CHARACTER | | | `NUMBER` | INTEGER | |
| `GUID` | CHARACTER | | | `TITLE1`..`TITLE3` | CHARACTER | |

### ASSEMBLY
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `ASSEMBLY_POS` | CHARACTER | | | `ASSEMBLY_NAME` | CHARACTER | |
| `LENGTH` | FLOAT | mm | | `MAINPART.LENGTH` | FLOAT | mm |
| `MAINPART.PROFILE` | CHARACTER | | | `MAINPART.FINISH` | CHARACTER | |
| `MAINPART.NAME` | CHARACTER | | | `WEIGHT_NET` | FLOAT | kg |
| `DATE` | INTEGER | dd.mm.yyyy | | `VOLUME` | FLOAT | m3 |
| `WEIGHT` | FLOAT | kg | | `MATERIAL_TYPE` | CHARACTER | |
| `MODEL_TOTAL` | INTEGER | | | `MAINPART.CLASS_ATTR` | CHARACTER | |
| `PROJECT.NAME` | CHARACTER | | | `PHASE` | INTEGER | |
| `CONTENTTYPE` | CHARACTER | | | `HEIGHT` | FLOAT | mm |
| `MAINPART.MATERIAL` | CHARACTER | | | `NUMBER` | INTEGER | |
| `AREA` | FLOAT | m2 | | `LOT_NUMBER` | INTEGER | |
| `HIERARCHY_LEVEL` | INTEGER | | | `PROJECT.BUILDER` | CHARACTER | |
| `GUID` | CHARACTER | | | `ID` | INTEGER | |
| `WIDTH` | FLOAT | mm | | `TITLE1`..`TITLE3` | CHARACTER | |

`HIERARCHY_LEVEL` matters for nested assemblies — filter on it to avoid double-counting sub-assemblies.

### BOLT
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `LENGTH` | FLOAT | mm | | `GRADE` | CHARACTER | |
| `DIAMETER` | FLOAT | mm | | `MODEL_TOTAL` | INTEGER | |
| `ASSEMBLY_POS` | CHARACTER | | | `TYPE`, `TYPE1`..`TYPE4` | CHARACTER | |
| `SITE_WORKSHOP` | CHARACTER | | | `MAIN_PART` | INTEGER | |
| `BOLT_STANDARD` | CHARACTER | | | `FINISH` | CHARACTER | |
| `NAME` | CHARACTER | | | `NAME_SHORT` | CHARACTER | |
| `WEIGHT` | FLOAT | kg | | `CONNECTED_ASSEMBLIES` | CHARACTER | |
| `MATERIAL` | CHARACTER | | | `NUMBER` | INTEGER | |
| `ASSEMBLY.MODEL_TOTAL` | INTEGER | | | `GUID` | CHARACTER | |

A bolt list is normally `DIAMETER` + `LENGTH` + `BOLT_STANDARD` + `SITE_WORKSHOP`, COMBINEd with
`oncombine = SUM` on the count — see `assets/skeleton_bolt_list.rpt`.

### REBAR
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `SIZE` | CHARACTER | | | `DIM_A`..`DIM_J` | FLOAT | mm |
| `LENGTH` | FLOAT | mm | | `DIM_R` | FLOAT | mm |
| `REBAR_POS` | CHARACTER | | | `CLASS` | CHARACTER | |
| `SHAPE` | CHARACTER | | | `CAST_UNIT_POS` | CHARACTER | |
| `GRADE` | CHARACTER | | | `MATERIAL` | CHARACTER | |
| `WEIGHT` | FLOAT | kg | | `LENGTH_MAX` | FLOAT | mm |
| `WEIGHT_TOTAL` | FLOAT | kg | | `MAINPART.NAME` | CHARACTER | |
| `NAME` | CHARACTER | | | `NUMBER_OF_BARS_IN_GROUP` | INTEGER | |
| `DATE` | INTEGER | dd.mm.yyyy | | `MODEL_TOTAL` | INTEGER | |

`WEIGHT` = one bar, `WEIGHT_TOTAL` = the group. `NUMBER_OF_BARS_IN_GROUP` is explicit where
`NUMBER` is ambiguous.

### DRAWING
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `PROJECT.NAME` | CHARACTER | | | `NAME_BASE` | CHARACTER | |
| `DATE_CREATE` | INTEGER | dd.mm.yyyy | | `ASSEMBLY.MODEL_TOTAL` | INTEGER | |
| `TITLE` | CHARACTER | | | `SCALE1`..`SCALE3` | CHARACTER | |
| `PROJECT.BUILDER` | CHARACTER | | | `PROJECT.INFO1` | CHARACTER | |
| `TITLE1`..`TITLE3` | CHARACTER | | | `MAINPART.FINISH` | CHARACTER | |
| `NAME` | CHARACTER | | | `PROJECT.ADDRESS` | CHARACTER | |
| `REVISION.MARK` | CHARACTER | | | `DATE_ISSUE` | INTEGER | dd.mm.yyyy |
| `ASSEMBLY.ASSEMBLY_POS` | CHARACTER | | | `REVISION.LAST_MARK` | CHARACTER | |
| `PROJECT.DESIGNER` | CHARACTER | | | `SIZE` | CHARACTER | |
| `TYPE` | CHARACTER | | | `PROJECT.OBJECT` | CHARACTER | |

`REVISION.LAST_*` reads the newest revision from a `DRAWING` row without nesting a `REVISION` row —
that's what a title block wants. A revision *table* nests `REVISION` rows instead.

### CAST_UNIT
| Attribute | Type | Unit | | Attribute | Type | Unit |
|---|---|---|---|---|---|---|
| `CAST_UNIT_POS` | CHARACTER | | | `MAINPART.WIDTH` | FLOAT | mm |
| `LENGTH` | FLOAT | mm | | `AREA` | FLOAT | m2 |
| `WEIGHT` | FLOAT | kg | | `MAINPART.CLASS_ATTR` | CHARACTER | |
| `MAINPART.NAME` | CHARACTER | | | `CAST_UNIT_REBAR_WEIGHT` | FLOAT | kg |
| `MAINPART.PROFILE` | CHARACTER | | | `MATERIAL_TYPE` | CHARACTER | |
| `MATERIAL` | CHARACTER | | | `WEIGHT_NET` | FLOAT | kg |
| `VOLUME` | FLOAT | m3 | | `CAST_UNIT_TYPE` | CHARACTER | |
| `MODEL_TOTAL` | INTEGER | | | `CAST_UNIT_POSITION_CODE` | CHARACTER | |
| `WIDTH` / `HEIGHT` | FLOAT | mm | | `VOLUME_NET_ONLY_CONCRETE_PARTS` | FLOAT | m3 |
| `MAINPART.LENGTH` | FLOAT | mm | | `TOP_LEVEL` | CHARACTER | |

`CAST_UNIT_REBAR_WEIGHT` gives the rebar in a unit without iterating REBAR rows — the usual want
on a precast schedule. `VOLUME` vs `VOLUME_NET_ONLY_CONCRETE_PARTS` decides whether embeds count.

## 5. Keeping this current

Names, datatypes and bindings come from the install and can be re-derived per version:

```powershell
scripts\Get-TeklaAttributes.ps1 -TeklaRoot C:\TeklaStructures\<ver> -ContentType PART -Format Markdown
scripts\Find-TeklaTemplateExamples.ps1 -Attribute ASSEMBLY.WEIGHT -Show   # who really uses it
```

If a mapping above disagrees with the extractor on a given install, the extractor wins — attribute
availability shifts between versions and environments. The English→attribute mapping and the traps
in §2 are judgement, not extractable data; edit them by hand.
