# Attribute glossary: what the 300 most-used attributes mean

Hand-written, in our own words, for the 300 attributes used most across the **2,685 shipped
Tekla 2026.0 templates** (`assets/template-index.json`; `USERDEFINED.*` and `ADVANCED_OPTION.*`
excluded). Type, unit and content types come from that version's `contentattributes_global.lst`;
`[n]` is how many shipped templates use the attribute. Meanings were checked against Trimble's
*Template attributes* PDF (2025/2026) and Tekla's own inquiry reports.

**How to use.** Grep for the name as you'd type it (`MAINPART.PROFILE`, `WELD_ACTUAL_LENGTH1`).
If `references/attribute-definitions.md` exists (built locally from Trimble's PDF), it is the
fuller authority, so cite it when the two differ and tell the user. **(unverified)** marks
meanings that neither the PDF nor a shipped label confirms. Treat those as inferred and say so.
Not listed here doesn't mean invalid: existence is `Get-TeklaAttributes.ps1`'s job.

**Prefixes** reach a related object: `MAINPART.` (assembly/cast unit → its main part),
`ASSEMBLY.` / `CAST_UNIT.` (part → its container), `PROJECT.`, `PHASE.`, `DRAWING.` (object → its
drawing), `REVISION.` (drawing → its revisions), `CURRENT_DRAWING.` (report placed on a drawing),
`REBAR.` (single bar → its group), `PRIMARY.` / `SECONDARY.` (weld/connection → its parts),
`PROFILE.` / `MATERIAL.` (part → catalog entry). A prefixed attribute means the same as the bare
one, just evaluated on the related object.

## Counting, paging and report context

- **NUMBER** [1095] `INTEGER/CHARACTER` · most content types: How many objects this output line stands for. On a `COMBINE`d row pair it with `oncombine = SUM` to get the quantity column; on `SINGLE_REBAR` and in hierarchies the meaning shifts per level (check the row's content type). Not the project number.
- **MODEL_TOTAL** [348] `INTEGER` · most content types: Count of objects in the whole model that share this object's position number. Ignores the report's selection and filters, so a filtered list shows whole-model totals.
- **PAGE** [495] `INTEGER` · most content types: Current page number of the report or drawing table.
- **PAGES** [134] `INTEGER` · most content types: Total page count. Reports only.
- **ROW_IN_PAGE** [15] `INTEGER` · most content types: Running row counter that restarts at 1 on each page. Counts hidden rows when used in a row `rule` but only visible rows in a formula, so copy it through a value field (`CopyField`) if a rule needs the visible count.
- **DATE** [824] `INTEGER dd.mm.yyyy` · most content types: Today's date at the moment the report or drawing table is produced, not a model or drawing date. `mm/dd/yyyy` when `XS_IMPERIAL_DATE` is set, else `dd.mm.yyyy`.
- **TIME** [513] `CHARACTER` · most content types: Clock time when the output is produced, as `hh:mm:ss` text.
- **TITLE1** [306] `CHARACTER` · most content types: First user title line typed in the Reports dialog (reports) or the drawing's title 1 (drawing tables). `TITLE2`/`TITLE3` are the next lines.
- **TITLE2** [212] `CHARACTER` · most content types: Second user title line; see `TITLE1`.
- **TITLE3** [166] `CHARACTER` · most content types: Third user title line; see `TITLE1`.
- **CONTENTTYPE** [224] `CHARACTER` · most content types: Name of the current row's content type (`PART`, `BOLT`, …). Handy in shared formulas and row rules.
- **CURRENT_USER** [37] `CHARACTER` · CONNECTION, DRAWING, HISTORY, REVISION: Login name of the person running the report (unverified: not in Trimble's attribute PDF; usage suggests the Windows user).
- **MODEL_PATH** [30] `CHARACTER` · HISTORY, REFERENCE_ASSEMBLY, REFERENCE_MODEL, REFERENCE_OBJECT: Folder path of the open model.
- **ID** [192] `INTEGER` · most content types: Internal object number. Changes between sessions and model-sharing read-ins, so never key anything on it; use `GUID`.
- **GUID** [236] `CHARACTER` · most content types: Permanent unique identifier of the object. The stable key for round trips and external systems. Report output may show it prefixed with `ID`.
- **OBJECT_DESCRIPTION** [14] `CHARACTER` · most content types: Object kind plus internal ID as text (e.g. a part's profile and `Id: 227`). Diagnostic only; inherits `ID`'s instability.
- **OWNER** [16] `CHARACTER` · most content types: Object owner as `domain\user` for native objects.
- **OBJECT_LOCKED** [20] `CHARACTER` · most content types: Value of the object's Locked user-defined attribute.
- **CLASS** [124] `CHARACTER` · MESH, REBAR, STRAND: **Two readings, verify before relying on it.** Trimble documents `CLASS` as a rule-only object category string (`PART`, `ASSEMBLY`, `BOLT`, …), yet the catalog binds it only to REBAR/MESH/STRAND and Tekla's rebar inquiry reports print it under the label "Class" as the bar's class number. For a part's class use `CLASS_ATTR`.

## Project, phase and location (via `PROJECT.` / `PHASE.` / `LOCATION_BREAKDOWN_STRUCTURE.`)

- **PROJECT.NUMBER** [901] `CHARACTER` · most content types: Project number from Project properties. **Text, not a number**: `"2024-A"` is legal, so keep `datatype = STRING`.
- **PROJECT.NAME** [752] `CHARACTER` · most content types: Project name from Project properties.
- **PROJECT.MODEL** [223] `CHARACTER` · most content types: Name of the model (its folder name).
- **PROJECT.BUILDER** [169] `CHARACTER` · most content types: Builder field of Project properties.
- **PROJECT.DESIGNER** [119] `CHARACTER` · most content types: Designer field of Project properties.
- **PROJECT.ADDRESS** [70] `CHARACTER` · most content types: Address field of Project properties.
- **PROJECT.OBJECT** [54] `CHARACTER` · most content types: Object field of Project properties (free text, often the building or structure name).
- **PROJECT.INFO1** [96] `CHARACTER` · most content types: Info 1 field of Project properties.
- **PROJECT.INFO2** [26] `CHARACTER` · most content types: Info 2 field of Project properties.
- **PROJECT.DESCRIPTION** [11] `CHARACTER` · most content types: Description field of Project properties.
- **PROJECT.LOCATION** [12] `CHARACTER` · most content types: Location field of Project properties.
- **PROJECT.DATE_START** [18] `INTEGER Date` · most content types: Project start date from Project properties.
- **DESCRIPTION** [64] `CHARACTER` · CONNECTION, PROJECT, REFERENCE_MODEL, REVISION, SPACE: Description text. On PROJECT the project description; on REVISION the revision's description.
- **INFO1** [20] `CHARACTER` · PROJECT, REVISION: Info 1 text. On PROJECT the project's Info 1; on REVISION the revision's Info 1.
- **INFO2** [15] `CHARACTER` · PROJECT, REVISION: Info 2 text; see `INFO1`.
- **PHASE** [123] `INTEGER` · most content types: Phase **number** (integer) the object belongs to. For the phase's name use `PHASE.NAME`.
- **PHASE.NAME** [45] `CHARACTER` · most content types: Name of the object's phase.
- **MAINPART.PHASE** [12] `INTEGER` · ASSEMBLY, CAST_UNIT, DRAWING: Phase number of the assembly's main part.
- **LOCATION_BREAKDOWN_STRUCTURE.LBS_FLOOR** [29] `CHARACTER` · ASSEMBLY, CAST_UNIT, POUR_OBJECT, POUR_UNIT, REFERENCE_ASSEMBLY, REFERENCE_OBJECT, SPACE: Floor/level of the object in the model's Location breakdown structure (unverified: not in Trimble's attribute PDF).
- **LOCATION_BREAKDOWN_STRUCTURE.LBS_SECTION** [21] `CHARACTER` · ASSEMBLY, CAST_UNIT, POUR_OBJECT, POUR_UNIT, REFERENCE_ASSEMBLY, REFERENCE_OBJECT, SPACE: Section in the Location breakdown structure (unverified).
- **LOCATION_BREAKDOWN_STRUCTURE.LBS_BUILDING** [20] `CHARACTER` · ASSEMBLY, CAST_UNIT, POUR_OBJECT, POUR_UNIT, REFERENCE_ASSEMBLY, REFERENCE_OBJECT, SPACE: Building in the Location breakdown structure (unverified).

## Marks, positions and prefixes

- **ASSEMBLY_POS** [624] `CHARACTER` · most content types: Assembly mark (prefix + number, e.g. `B-12`). On a part, bolt or rebar it is the mark of the assembly/rebar assembly that contains it. Text: sorts alphabetically, so `B10` comes before `B2`.
- **PART_POS** [405] `CHARACTER` · ANTIMATERIAL, PART: Single-part mark (e.g. `p12`). Blank for objects that aren't parts.
- **CAST_UNIT_POS** [255] `CHARACTER` · CAST_UNIT, MESH, PART, REBAR, STRAND: Cast unit mark (prefix + number). On parts and rebar, the mark of their cast unit.
- **REBAR_POS** [276] `CHARACTER` · MESH, REBAR, SINGLE_REBAR: Rebar position mark, formatted by `XS_REBAR_POSITION_NUMBER_FORMAT_STRING` (tapered bars in rebar sets have their own format option).
- **MESH_POS** [57] `CHARACTER` · MESH: Mesh position mark, formatted by an advanced option.
- **STRAND_POS** [18] `CHARACTER` · STRAND: Strand position mark (prefix + running number).
- **GROUP_POS** [28] `CHARACTER` · REBAR: Position of a tapered bar group inside a rebar set, formatted by its own advanced option (falls back to the normal rebar format).
- **REBAR_SEQ_POS** [16] `CHARACTER` · MESH, REBAR, SINGLE_REBAR, STRAND: Running sequence number of a reinforcement object inside its cast unit or pour unit.
- **PRELIM_MARK** [46] `CHARACTER` · PART: The Preliminary mark user-defined attribute of a part.
- **ASSEMBLY_PREFIX** [15] `CHARACTER` · ASSEMBLY, PART, REBAR_ASSEMBLY: Assembly prefix set in part/assembly properties.
- **ASSEMBLY_DEFAULT_PREFIX** [10] `CHARACTER` · PART: The default assembly prefix from part properties.
- **PART_PREFIX** [14] `CHARACTER` · PART: Part prefix set in part properties.
- **CAST_UNIT_PREFIX** [13] `CHARACTER` · CAST_UNIT: Cast unit prefix set in part properties.
- **PREFIX** [11] `CHARACTER` · ASSEMBLY, CAST_UNIT, MESH, PART, REBAR, REBAR_ASSEMBLY, STRAND: Numbering prefix of the object (unverified: not in Trimble's attribute PDF; prefer the specific `ASSEMBLY_PREFIX`/`PART_PREFIX`/`CAST_UNIT_PREFIX`).
- **ASSEMBLY_POSITION_CODE** [20] `CHARACTER` · ASSEMBLY, CAST_UNIT, REFERENCE_ASSEMBLY: Grid location code of the assembly, worked out from the nearest grid lines (e.g. `A-B/1`).
- **CAST_UNIT_POSITION_CODE** [29] `CHARACTER` · CAST_UNIT: Grid location code of the cast unit; same scheme as `ASSEMBLY_POSITION_CODE`.
- **ACN** [25] `INTEGER` · PART: Control number of the part (from the control-number tool).
- **MAIN_PART** [103] `INTEGER` · BOLT, PART, STUD: 1 for the main part of its assembly, 0 otherwise. Sort a part list descending on it to put the main part first.
- **HIERARCHY_LEVEL** [100] `INTEGER` · ASSEMBLY, CAST_UNIT, REBAR_ASSEMBLY: Nesting level of an assembly: 0 top of the hierarchy, higher numbers for sub-assemblies deeper down (Trimble also gives 1 and 2 special meanings for nested assemblies; check the PDF if it matters).
- **LOT_NUMBER** [39] `INTEGER` · ASSEMBLY, CAST_UNIT: Lot number of the assembly or cast unit. Not available on PART directly; go through `ASSEMBLY.`.
- **SUB_ID** [79] `type not in catalog` · SINGLE_REBAR, SINGLE_STRAND: Running index of one bar inside its bar group (SINGLE_REBAR rows).

## Names, profiles and materials

- **NAME** [615] `CHARACTER` · most content types: Object name; what that is depends on the content type (part name, bolt catalog name, connection name, the drawing's type+mark like `A [K1]`, …). If the object has none, Tekla falls back to the next level up, up to the project name. **ASSEMBLY doesn't bind it:** use `ASSEMBLY_NAME` or `MAINPART.NAME`.
- **ASSEMBLY_NAME** [98] `CHARACTER` · ASSEMBLY, REBAR_ASSEMBLY: Name of the assembly (unverified: not in Trimble's attribute PDF; shipped templates use `MAINPART.NAME` ~4× more often).
- **CAST_UNIT_NAME** [21] `CHARACTER` · CAST_UNIT: Name of the cast unit (unverified: not in Trimble's attribute PDF).
- **NAME_SHORT** [23] `CHARACTER` · BOLT, HOLE, NUT, STUD, WASHER: Short catalog name of a bolt/nut/washer/stud (unverified: not in Trimble's attribute PDF).
- **PRODUCT_NAME** [41] `CHARACTER` · PART: Product name of a part (unverified: not in Trimble's attribute PDF).
- **PROFILE** [541] `CHARACTER` · ANTIMATERIAL, PART: Profile string of the part (`HEA300`, `PL10*200`); on an assembly or cast unit, the main part's. Other profile properties are reached as `PROFILE.<attr>`.
- **PROFILE_TYPE** [84] `CHARACTER` · ANTIMATERIAL, PART: DSTV profile type code of the part (I, U, L, B for plate, …). Good for grouping a list by section family.
- **MATERIAL** [505] `CHARACTER` · most content types: Material grade (`S355J2`, `C30/37`). For an assembly, its main part's; for a bolt, the grade from the bolt assembly catalog.
- **MATERIAL_TYPE** [121] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: Material family: `STEEL`, `CONCRETE`, `TIMBER` or `MISCELLANEOUS`. The usual switch for steel-vs-concrete branches.
- **MATERIAL.PLATE_DENSITY** [21] `FLOAT` · PART: Plate density of the part's material from the material catalog (kg/m³).
- **GRADE** [272] `CHARACTER` · BOLT, MESH, NUT, REBAR, STRAND, STUD, WASHER: Grade of bolts, nuts, washers, studs, rebar, mesh and strand. **A part has no `GRADE`**: use `MATERIAL`.
- **FINISH** [77] `CHARACTER` · BOLT, HOLE, NUT, PART, STUD, WASHER: Finish text from part properties (paint, galvanising, …). Blank for most other objects.
- **CLASS_ATTR** [39] `CHARACTER` · MESH, PART, REBAR, SURFACE: Class number set in part, rebar or surface properties. The right attribute for a part's class.
- **TYPE** [129] `CHARACTER` · most content types: Object type or standard; meaning depends on the content type (bolt standard, drawing type, mesh type, …).
- **TYPENAME** [12] `CHARACTER` · LOAD, LOADGROUP: Type name of a load or load group (unverified: not in Trimble's attribute PDF).
- **CATALOG_NAME** [60] `CHARACTER` · MESH, REBAR: Mesh identifier, e.g. a standard mesh name from the mesh catalog or `Custom Mesh`.
- **CODE** [11] `CHARACTER` · REFERENCE_MODEL, SURFACING: Short code of a surface treatment (from `product_finishes.dat`).
- **SURFACING_NAME** [12] `CHARACTER` · SURFACING: Name of a surface treatment (from `product_finishes.dat`).
- **CAST_UNIT_TYPE** [40] `CHARACTER` · CAST_UNIT: `Precast` or `Cast in place`, as text.
- **POUR_TYPE** [41] `CHARACTER` · POUR_OBJECT: Type of the pour object (unverified: not in Trimble's attribute PDF).
- **POUR_NUMBER** [47] `CHARACTER` · POUR_OBJECT: Pour number of the pour object (unverified: not in Trimble's attribute PDF).
- **CONCRETE_MIXTURE** [32] `CHARACTER` · POUR_OBJECT: Concrete mixture of the pour object (unverified: not in Trimble's attribute PDF).
- **REBAR_ASSEMBLY_TYPE** [18] `CHARACTER` · REBAR_ASSEMBLY: Type chosen for a rebar assembly (cage, bent mesh, braced girder, or blank).

## Dimensions and geometry

- **LENGTH** [822] `FLOAT mm` · most content types: Length of the object in mm, after cuts, fittings and end offsets. For the uncut length use `LENGTH_GROSS`. On a WELD, see the weld section.
- **LENGTH_GROSS** [51] `FLOAT mm` · most content types: Length before cuts are applied (parts, assemblies, bolts).
- **WIDTH** [247] `FLOAT mm` · ANTIMATERIAL, ASSEMBLY, CAST_UNIT, DRAWING, MESH, PART, REBAR_ASSEMBLY: Width of a part or assembly, mm. On DRAWING, the sheet width.
- **HEIGHT** [166] `FLOAT mm` · ANTIMATERIAL, ASSEMBLY, CAST_UNIT, DRAWING, PART, REBAR_ASSEMBLY, SPACE: Height, mm. On ASSEMBLY it's the main part's height; on DRAWING the sheet height.
- **SIZE** [331] `CHARACTER` · DRAWING, MESH, REBAR, STRAND: On DRAWING: the sheet size text (e.g. `210x297`). On REBAR/MESH/STRAND: the nominal bar size, also text.
- **DIAMETER** [138] `FLOAT mm` · BOLT, HOLE, NUT, STUD, WASHER: Diameter in mm. What it measures depends on the content type: bolt shank, hole, the inner diameter of a nut or washer, stud.
- **COG_X** [28] `FLOAT mm` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY, WELD: Centre of gravity X, global coordinates (mm).
- **COG_Y** [28] `FLOAT mm` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY, WELD: Centre of gravity Y, global coordinates (mm).
- **COG_Z** [28] `FLOAT mm` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY, WELD: Centre of gravity Z, global coordinates (mm).
- **START_X** [25] `FLOAT mm` · PART: X of the part's start handle (the yellow one), mm. Add a suffix such as `_BASEPOINT` for other coordinate systems.
- **START_Y** [25] `FLOAT mm` · PART: Y of the part's start handle; see `START_X`.
- **START_Z** [29] `FLOAT mm` · PART: Z of the part's start handle; see `START_X`.
- **END_X** [27] `FLOAT mm` · PART: X of the part's end handle (the magenta one), mm; suffixes as for `START_X`.
- **END_Y** [27] `FLOAT mm` · PART: Y of the part's end handle; see `END_X`.
- **END_Z** [27] `FLOAT mm` · PART: Z of the part's end handle; see `END_X`.
- **END1_SKEW** [39] `INTEGER` · PART: 1 if the part's first end is cut or fitted at an angle, 0 if square.
- **END2_SKEW** [39] `INTEGER` · PART: Same as `END1_SKEW` for the second end.
- **END1_ANGLE_Y** [22] `FLOAT Degrees` · PART: End-cut angle of the first end about the local y direction (profiled parts), degrees.
- **END1_ANGLE_Z** [22] `FLOAT Degrees` · PART: End-cut angle of the first end about the local z direction, degrees.
- **END2_ANGLE_Y** [22] `FLOAT Degrees` · PART: End-cut angle of the second end, local y, degrees.
- **END2_ANGLE_Z** [22] `FLOAT Degrees` · PART: End-cut angle of the second end, local z, degrees.
- **BOUNDING_BOX_MAX_Z** [13] `FLOAT mm` · ASSEMBLY, CAST_UNIT, PART, REFERENCE_ASSEMBLY, REFERENCE_MODEL, REFERENCE_OBJECT: Highest Z of the object's bounding box, measured from the model origin (one of the `BOUNDING_BOX_MIN/MAX_X/Y/Z` family).
- **TOP_LEVEL** [52] `CHARACTER` · ANTIMATERIAL, ASSEMBLY, CAST_UNIT, PART, POUR_OBJECT, REBAR, REBAR_ASSEMBLY, SINGLE_REBAR: Top elevation of the object as formatted text (units and precision come from `MarkDimensionFormat.dim`, not the template). Text, so don't do arithmetic on it.
- **BOTTOM_LEVEL** [30] `CHARACTER` · ANTIMATERIAL, ASSEMBLY, CAST_UNIT, PART, POUR_OBJECT, REBAR, SINGLE_REBAR: Bottom elevation as formatted text; same caveats as `TOP_LEVEL`.
- **TOP_LEVEL_GLOBAL** [16] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, POUR_OBJECT, REBAR, SINGLE_REBAR: Top elevation along the global axis rather than the object's local up; formatted text.
- **BOTTOM_LEVEL_GLOBAL** [12] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, POUR_OBJECT, REBAR, SINGLE_REBAR: Bottom elevation along the global axis; formatted text.
- **ASSEMBLY_TOP_LEVEL** [15] `CHARACTER` · ASSEMBLY, PART, REBAR_ASSEMBLY: Top elevation of the whole assembly, formatted text.
- **ASSEMBLY_BOTTOM_LEVEL** [14] `CHARACTER` · ASSEMBLY, PART, REBAR_ASSEMBLY: Bottom elevation of the whole assembly, formatted text.
- **CAST_UNIT_HEIGHT_ONLY_CONCRETE_PARTS** [10] `FLOAT mm` · CAST_UNIT: Cast unit height counting only its concrete parts (embeds ignored).

## Weight, area and volume

- **WEIGHT** [523] `FLOAT kg` · most content types: Weight in kg. For a part with a catalog cross-section it's area × length × density, which equals `WEIGHT_GROSS`; for parametric profiles it's the net, cut-aware value. Assemblies sum their parts. Surface treatment is included.
- **WEIGHT_NET** [158] `FLOAT kg` · ASSEMBLY, CAST_UNIT, MESH, PART, REBAR_ASSEMBLY: Fabricated weight in kg, with cuts and holes deducted (corner radii ignored). Assemblies sum part net weights; bolts give the bolt weight.
- **WEIGHT_GROSS** [60] `FLOAT kg` · ASSEMBLY, CAST_UNIT, MESH, PART, REBAR_ASSEMBLY: Weight of the stock material needed, in kg: catalog profiles from length × section, plates from their overall rectangle, with no deductions for cuts.
- **WEIGHT_TOTAL** [148] `FLOAT kg` · MESH, REBAR, STRAND: Whole bar-group weight on REBAR/MESH/STRAND (`WEIGHT` is one bar). **Not bound to PART or ASSEMBLY**: total those in the footer with `Total()`.
- **WEIGHT_M** [13] `FLOAT kg` · PART: Profile weight per metre from the catalog; for parametric profiles, weight ÷ length.
- **PROFILE_WEIGHT** [10] `FLOAT kg` · PART: Part weight computed from the catalog weight per metre; falls back to other methods when the catalog has no value.
- **PROFILE.WEIGHT_PER_UNIT_LENGTH** [34] `FLOAT` · PART: Catalog weight per metre of the part's profile, kg/m. Bare `WEIGHT_PER_UNIT_LENGTH` is the rebar one.
- **AREA** [202] `FLOAT m2` · most content types: Surface area in m². Plates and parametric profiles: net area of all faces. Catalog profiles with a cover area defined: gross area from length × cover area per metre, ignoring end faces and cuts.
- **AREA_NET** [55] `FLOAT m2` · MESH, PART, STRAND, SURFACE: Net surface area of the fabricated part (zero for non-parts).
- **AREA_GROSS** [38] `FLOAT m2` · MESH, PART, STRAND, SURFACE: Gross area. Equals `AREA` for profiles; for plates, the bounding rectangle (length × width).
- **AREA_PROJECTION_XY_NET** [46] `FLOAT m2` · ASSEMBLY, CAST_UNIT, PART: Net area of the object's "shadow" on its local XY plane (plan footprint).
- **VOLUME** [171] `FLOAT m3` · ASSEMBLY, CAST_UNIT, PART, POUR_OBJECT, SPACE, SURFACING: Volume after holes and cuts. **Calculates in mm³** even though the catalog lists m³. Fine as a formatted field; in arithmetic convert explicitly with `double(format(…))`.
- **VOLUME_NET** [28] `FLOAT m3` · ASSEMBLY, CAST_UNIT, PART: Volume with holes and cuts taken into account; same unit caveat as `VOLUME`.
- **VOLUME_ONLY_CONCRETE_PARTS** [16] `FLOAT m3` · CAST_UNIT: Cast unit volume from its concrete parts only (rebar and embeds excluded).
- **VOLUME_NET_ONLY_CONCRETE_PARTS** [24] `FLOAT m3` · CAST_UNIT: Cast unit volume from the concrete parts' solids. Parts whose profile has a manually defined section area are skipped.
- **CAST_UNIT_REBAR_WEIGHT** [40] `FLOAT kg` · CAST_UNIT: Total weight of the reinforcement in a cast unit, kg.

## Reinforcement

- **SHAPE** [267] `CHARACTER` · MESH, REBAR, SINGLE_REBAR, STRAND: Environment-specific bending shape code of a bar.
- **SHAPE_INTERNAL** [55] `CHARACTER` · MESH, REBAR, SINGLE_REBAR: Tekla's own internal bending-type code (e.g. `2_1`), the same in every environment.
- **DIM_A** [139] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg A of a bent bar, mm. Which leg is "A" is set per shape in the environment's `rebar_schedule_config.inp`, so the letters can differ between environments.
- **DIM_B** [142] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg B of a bent bar; see `DIM_A`.
- **DIM_C** [138] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg C; see `DIM_A`.
- **DIM_D** [133] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg D; see `DIM_A`.
- **DIM_E** [131] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg E; see `DIM_A`.
- **DIM_F** [107] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg F; see `DIM_A`.
- **DIM_G** [85] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Leg G; see `DIM_A`.
- **DIM_H1** [68] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension H1 per `rebar_schedule_config.inp`.
- **DIM_H2** [28] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension H2 per `rebar_schedule_config.inp`.
- **DIM_I** [31] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension I per `rebar_schedule_config.inp`.
- **DIM_J** [68] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension J per `rebar_schedule_config.inp`.
- **DIM_K1** [35] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension K1 per `rebar_schedule_config.inp`.
- **DIM_K2** [24] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension K2 per `rebar_schedule_config.inp`.
- **DIM_O** [36] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension O per `rebar_schedule_config.inp`.
- **DIM_R** [79] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Bending radius per `rebar_schedule_config.inp`.
- **DIM_TD** [68] `FLOAT mm` · MESH, REBAR, SINGLE_REBAR, STRAND: Shape dimension TD per `rebar_schedule_config.inp`.
- **DIM_A_MAX** [23] `FLOAT mm` · MESH, REBAR, STRAND: Largest leg A across a tapered group (the `_MAX`/`_MIN` variants exist for every leg).
- **DIM_B_MAX** [23] `FLOAT mm` · MESH, REBAR, STRAND: Largest leg B in a tapered group.
- **DIM_C_MAX** [23] `FLOAT mm` · MESH, REBAR, STRAND: Largest leg C in a tapered group.
- **DIM_D_MAX** [16] `FLOAT mm` · MESH, REBAR, STRAND: Largest leg D in a tapered group.
- **DIM_E_MAX** [16] `FLOAT mm` · REBAR, STRAND: Largest leg E in a tapered group.
- **DIM_A_MIN** [16] `FLOAT mm` · MESH, REBAR, STRAND: Smallest leg A in a tapered group.
- **DIM_B_MIN** [16] `FLOAT mm` · MESH, REBAR, STRAND: Smallest leg B in a tapered group.
- **DIM_C_MIN** [16] `FLOAT mm` · MESH, REBAR, STRAND: Smallest leg C in a tapered group.
- **DIM_D_MIN** [16] `FLOAT mm` · MESH, REBAR, STRAND: Smallest leg D in a tapered group.
- **DIM_E_MIN** [16] `FLOAT mm` · REBAR, STRAND: Smallest leg E in a tapered group.
- **DIM_X_MAX** [13] `FLOAT mm` · REBAR, STRAND: Largest value of a shape dimension across a tapered group.
- **DIM_X_MIN** [13] `FLOAT mm` · REBAR, STRAND: Smallest value of a shape dimension across a tapered group.
- **ANG_U** [42] `FLOAT Degrees` · MESH, REBAR, SINGLE_REBAR, STRAND: Bend angle U per `rebar_schedule_config.inp`, degrees.
- **ANG_V** [42] `FLOAT Degrees` · MESH, REBAR, SINGLE_REBAR, STRAND: Bend angle V per `rebar_schedule_config.inp`, degrees.
- **ANG_U_MAX** [13] `FLOAT Degrees` · REBAR, STRAND: Largest angle U across a tapered group.
- **ANG_U_MIN** [13] `FLOAT Degrees` · REBAR, STRAND: Smallest angle U across a tapered group.
- **ANG_V_MAX** [13] `FLOAT Degrees` · REBAR, STRAND: Largest angle V across a tapered group.
- **ANG_V_MIN** [13] `FLOAT Degrees` · REBAR, STRAND: Smallest angle V across a tapered group.
- **LENGTH_MAX** [72] `FLOAT mm` · MESH, REBAR, STRAND: Longest bar in a bar group, mm.
- **LENGTH_MIN** [65] `FLOAT mm` · MESH, REBAR, STRAND: Shortest bar in a bar group, mm.
- **GROUP_TYPE** [36] `INTEGER` · LOAD, MESH, REBAR, STRAND: Bar group kind as a number: 0 normal, 1–4 the tapered variants, 5 spiral.
- **IS_REBARSET_BAR** [13] `INTEGER` · REBAR, SINGLE_REBAR: 1 if the bar belongs to a rebar set, else 0.
- **CC_LONG** [14] `CHARACTER mm` · MESH: Centre-to-centre spacing of a mesh's longitudinal bars.
- **CC_CROSS** [12] `CHARACTER mm` · MESH: Centre-to-centre spacing of a mesh's cross bars.
- **CC_DIAMETER_LONG** [10] `CHARACTER mm` · MESH: All diameters of a mesh's longitudinal bars, as count×size text (e.g. `5*10 25*8`).
- **STRAND_PULL_FORCE** [33] `FLOAT kN` · REBAR, STRAND: Pull force of a strand, kN.
- **STRAND_N_PATTERN** [13] `INTEGER` · STRAND: Number of distinct cross-sections in a strand pattern.
- **REBAR.SIZE** [76] `CHARACTER` · SINGLE_REBAR: On a SINGLE_REBAR row: the parent bar group's size.
- **REBAR.REBAR_POS** [62] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's position mark.
- **REBAR.GRADE** [58] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's grade.
- **REBAR.GROUP_TYPE** [44] `INTEGER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's type number (see `GROUP_TYPE`).
- **REBAR.GROUP_POS** [28] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: the parent's tapered-group position (see `GROUP_POS`).
- **REBAR.NUMBER** [21] `INTEGER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's count.
- **REBAR.NUMBER_OF_BARS_IN_GROUP** [17] `INTEGER` · SINGLE_REBAR: On SINGLE_REBAR: how many bars the group holds.
- **REBAR.WEIGHT_TOTAL_IN_GROUP** [15] `FLOAT` · SINGLE_REBAR: On SINGLE_REBAR: total weight of all bars in the group.
- **REBAR.CAST_UNIT_POS** [15] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: mark of the cast unit the bar belongs to.
- **REBAR.NAME** [13] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's name.
- **REBAR.CLASS** [10] `CHARACTER` · SINGLE_REBAR: On SINGLE_REBAR: the parent group's `CLASS` (see the caveat on `CLASS`).

## Welds

- **WELD_TYPE1** [33] `CHARACTER` · WELD: Weld type chosen above the line (the symbol type, e.g. fillet or bevel).
- **WELD_TYPE2** [30] `CHARACTER` · WELD: Weld type below the line.
- **WELD_SIZE1** [30] `FLOAT` · WELD: Size typed above the line.
- **WELD_SIZE2** [27] `FLOAT` · WELD: Size typed below the line.
- **WELD_SIZE_PREFIX_ABOVE** [11] `CHARACTER` · WELD: Size prefix above the line (e.g. `a`, `s`).
- **WELD_SIZE_PREFIX_BELOW** [11] `CHARACTER` · WELD: Size prefix below the line.
- **WELD_ACTUAL_LENGTH1** [15] `FLOAT mm` · WELD: Seam length above the line, measured from the seam's start point to its end point (summed over seams). **Gaps of an intermittent weld are included**, despite the "Actual length" label in Tekla's weld inquiry.
- **WELD_ACTUAL_LENGTH2** [15] `FLOAT mm` · WELD: Same as `WELD_ACTUAL_LENGTH1`, below the line.
- **WELD_LENGTH1** [13] `FLOAT mm` · WELD: The Length value typed above the line: the **segment** length of an intermittent weld, not the seam length.
- **WELD_LENGTH2** [13] `FLOAT mm` · WELD: Segment length typed below the line.
- **WELD_PERIOD1** [10] `FLOAT` · WELD: The Pitch value typed above the line (intermittent welds). Whether that's centre-to-centre or the gap isn't stated in the docs; check one weld.
- **WELD_PERIOD2** [10] `FLOAT` · WELD: The Pitch value below the line; see `WELD_PERIOD1`.
- **WELD_INCREMENT_AMOUNT1** [11] `INTEGER` · WELD: Number of increments of an intermittent weld above the line.
- **WELD_INCREMENT_AMOUNT2** [11] `INTEGER` · WELD: Number of increments below the line.
- **WELD_FILLTYPE1** [21] `CHARACTER` · WELD: Contour above the line: none, flush, convex or concave.
- **WELD_FILLTYPE2** [21] `CHARACTER` · WELD: Contour below the line.
- **WELD_FINISH1** [21] `CHARACTER` · WELD: Finish symbol above the line.
- **WELD_FINISH2** [21] `CHARACTER` · WELD: Finish symbol below the line.
- **WELD_ROOT_FACE_THICKNESS** [13] `FLOAT mm` · WELD: Root face thickness (welding lists).
- **WELD_EDGE_AROUND** [12] `CHARACTER` · WELD: `Edge` when one edge is welded, `Around` for all-round welds.
- **WELD_ASSEMBLYTYPE** [15] `CHARACTER` · WELD: `Site` or `Workshop`. Welding lists only.
- **WELD_TEXT** [18] `CHARACTER` · WELD: The weld's reference text, up to 80 characters; widen the field to show it all.
- **WELD_VOLUME** [10] `FLOAT mm3` · WELD: Volume of the solid weld in mm³; the basis for weld-metal weight. **0 when the weld type has no solid or the solid failed**, so blanks in a weight total are silent.
- **WELD_ERRORLIST** [11] `CHARACTER` · WELD: Error codes for a problem weld (E1–E7: wrong location, parts not touching, …).
- **TYPE1** [14] `CHARACTER` · BOLT, WELD: Bolts: standards of the bolt and each washer/nut slot, slash-separated. Also bound to WELD (unverified meaning there).
- **TYPE2** [30] `CHARACTER` · BOLT, WELD: Bolts: 1/0 string marking which washer and nut slots are present (e.g. `10011`). Also bound to WELD (unverified meaning there).
- **TYPE3** [12] `CHARACTER` · BOLT: Bolts: like `TYPE2` but `X`/`o` (e.g. `XooXX`).
- **TYPE4** [13] `CHARACTER` · BOLT: Bolts: like `TYPE1` but lists only the parts that are present.
- **PRIMARY.ASSEMBLY_POS** [18] `CHARACTER` · CONNECTION, WELD: On WELD/CONNECTION: assembly mark of the main (primary) welded or connected part.
- **PRIMARY.PART_POS** [16] `CHARACTER` · CONNECTION, WELD: On WELD/CONNECTION: part mark of the primary part.
- **SECONDARY.PART_POS** [12] `CHARACTER` · WELD: On WELD: part mark of the secondary part.
- **SECONDARY_1.ASSEMBLY_POS** [11] `CHARACTER` · BOLT, CONNECTION: On BOLT/CONNECTION: assembly mark of the first secondary part.

## Bolts and connections

- **BOLT_STANDARD** [78] `CHARACTER` · BOLT, NUT, STUD, WASHER: Bolt standard as in the bolt assembly catalog (e.g. `7968`).
- **SITE_WORKSHOP** [83] `CHARACTER` · BOLT, HOLE, NUT, STUD, WASHER: `Site` or `Shop` for bolts and studs (translated by message files).
- **BOLT.SITE_WORKSHOP** [11] `CHARACTER` · HOLE, NUT, WASHER: On HOLE/NUT/WASHER rows: the owning bolt's site/shop flag.
- **CONNECTED_ASSEMBLIES** [22] `CHARACTER` · BOLT, HOLE, NUT, WASHER: Space-separated marks of the assemblies a bolt joins (e.g. `A17 A18`). In assembly-bolt lists the current assembly is left out.
- **CONNECTION_CODE** [24] `CHARACTER` · CONNECTION: Connection code from the connection dialog (connection lists).
- **CONNECTION_NUMBER** [17] `INTEGER` · CONNECTION: Number of the connection.
- **CONNECTION_ERROR** [11] `INTEGER` · CONNECTION: Connection status: 1 green, 2 yellow, 3 red symbol, 4 failed design check.

## Drawings and revisions

- **TITLE** [110] `CHARACTER` · DRAWING, REFERENCE_MODEL: Drawing title from drawing properties. Also usable on parts/assemblies to list their drawings.
- **NAME_BASE** [53] `CHARACTER` · DRAWING: Drawing mark only (`[K1]`), without the type letter that `NAME` adds (`A [K1]`).
- **DATE_CREATE** [189] `INTEGER dd.mm.yyyy` · DRAWING, REVISION: Drawing creation date. In drawing tables it shows the **last revision's** date; in REVISION rows each revision's.
- **DATE_ISSUE** [39] `INTEGER dd.mm.yyyy` · DRAWING: Drawing issue date.
- **DATE_MODIFY** [17] `INTEGER dd.mm.yyyy` · DRAWING: Date the drawing last changed.
- **DATE_PLOT** [16] `INTEGER dd.mm.yyyy` · DRAWING: Date the drawing was last printed.
- **DATE_LAST** [28] `INTEGER dd.mm.yyyy` · —: Date of the drawing's last revision (all revisions in REVISION rows).
- **DATE_CHECKED** [10] `INTEGER dd.mm.yyyy` · REVISION: Checked date from Revision handling.
- **SCALE1** [47] `CHARACTER` · DRAWING: Largest view scale on the drawing; `SCALE2`… the next ones down (up to 5).
- **SCALE2** [35] `CHARACTER` · DRAWING: Second-largest view scale; see `SCALE1`.
- **SCALE3** [17] `CHARACTER` · DRAWING: Third-largest view scale; see `SCALE1`.
- **PLOTFILE** [12] `CHARACTER` · DRAWING: File name of the drawing's `.dg` file.
- **DR_PART_POS** [30] `CHARACTER` · DRAWING: Mark of the drawing's main object: the assembly mark on assembly and cast unit drawings, the part mark otherwise.
- **DR_DEFAULT_HOLE_SIZE** [16] `FLOAT mm` · DRAWING: Default bolt hole size set in drawing properties (for notes in the drawing template).
- **DR_DEFAULT_WELD_SIZE** [11] `FLOAT mm` · DRAWING: Default weld size set in drawing weld properties (for template notes).
- **MARK** [72] `CHARACTER` · REVISION: Revision mark (REVISION rows).
- **CREATED_BY** [37] `CHARACTER` · ANTIMATERIAL, PART, REVISION: Created by from Revision handling (REVISION rows). Also bound to PART (unverified meaning there).
- **CHECKED_BY** [20] `CHARACTER` · REVISION: Checked by from Revision handling, or the part's Checked by UDA.
- **TEXT1** [14] `CHARACTER` · —: Revision description/info text; usable as a print-file name element too.
- **REVISION.MARK** [106] `CHARACTER` · DRAWING: On DRAWING: the drawing's revision mark.
- **REVISION.NUMBER** [42] `INTEGER` · DRAWING: On DRAWING: revision number.
- **REVISION.LAST_MARK** [33] `CHARACTER` · DRAWING: On DRAWING: mark of the latest revision.
- **REVISION.LAST_DATE_CREATE** [15] `INTEGER Date` · DRAWING: On DRAWING: date of the latest revision.
- **REVISION.LAST_APPROVED_BY** [11] `CHARACTER` · DRAWING: On DRAWING: approver of the latest revision.
- **REVISION.LAST_CHECKED_BY** [11] `CHARACTER` · DRAWING: On DRAWING: checker of the latest revision.
- **REVISION.LAST_DATE_APPROVED** [11] `INTEGER Date` · DRAWING: On DRAWING: approval date of the latest revision.
- **DRAWING.REVISION.MARK** [39] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: revision mark of its drawing.
- **DRAWING.REVISION.LAST_MARK** [18] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: latest revision mark of its drawing.
- **DRAWING.TITLE** [31] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's title.
- **DRAWING.TITLE1** [21] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's title 1.
- **DRAWING.TITLE2** [24] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's title 2.
- **DRAWING.NAME** [12] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's name (type + mark).
- **DRAWING.NAME_BASE** [13] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's mark only.
- **DRAWING.DATE_CREATE** [20] `INTEGER Date` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's date (see `DATE_CREATE`).
- **DRAWING.SCALE1** [14] `CHARACTER` · ASSEMBLY, CAST_UNIT, PART, REBAR_ASSEMBLY: From a part/assembly row: its drawing's largest view scale.
- **CURRENT_DRAWING.DATE_CREATE** [25] `INTEGER Date` · ASSEMBLY, PART, REBAR_ASSEMBLY: In a report embedded on a drawing: that drawing's date.
- **HISTORY.CREATED** [9] `type not in catalog` · CONNECTION, DRAWING, PART, REBAR, SURFACING: Date the object was created (model history).
- **HISTORY.CREATED_BY** [9] `CHARACTER` · CONNECTION, DRAWING, PART, REBAR, SURFACING: User who created the object (model history).
- **HISTORY.MODIFIED** [9] `type not in catalog` · CONNECTION, DRAWING, PART, REBAR, SURFACING: Date the object was last modified (model history).

## Reaching related objects (prefixed forms)

- **MAINPART.PROFILE** [355] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Profile of the assembly's / cast unit's main part.
- **MAINPART.NAME** [340] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Name of the main part. The usual way to put a name on an assembly row.
- **MAINPART.MATERIAL** [149] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: Material grade of the main part.
- **MAINPART.LENGTH** [106] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: Length of the main part (not the assembly's overall length).
- **MAINPART.WIDTH** [53] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: Width of the main part.
- **MAINPART.HEIGHT** [40] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: Height of the main part.
- **MAINPART.FINISH** [101] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Finish of the main part.
- **MAINPART.CLASS_ATTR** [64] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: Class number of the main part.
- **MAINPART.MATERIAL_TYPE** [38] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Material family of the main part.
- **MAINPART.PART_POS** [34] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Part mark of the main part.
- **MAINPART.ACN** [31] `INTEGER` · ASSEMBLY, CAST_UNIT, DRAWING: Control number of the main part.
- **MAINPART.NUMBER** [23] `INTEGER` · ASSEMBLY, CAST_UNIT, DRAWING: `NUMBER` evaluated on the main part.
- **MAINPART.PROFILE_TYPE** [21] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: DSTV profile type of the main part.
- **MAINPART.PROFILE.WIDTH** [19] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: Catalog width of the main part's profile.
- **MAINPART.PROFILE.HEIGHT** [14] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: Catalog height of the main part's profile.
- **MAINPART.BOTTOM_LEVEL** [13] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Bottom level of the main part (formatted text).
- **MAINPART.TOP_LEVEL** [13] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING: Top level of the main part (formatted text).
- **MAINPART.END_X** [12] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: End-handle X of the main part.
- **MAINPART.END_Y** [12] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: End-handle Y of the main part.
- **MAINPART.END_Z** [11] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING: End-handle Z of the main part.
- **MAINPART.IS_ITEM** [12] `INTEGER` · ASSEMBLY, CAST_UNIT, DRAWING: 1 if the main part is an item (a 3D-shape object), else 0.
- **MAINPART.GUID** [11] `CHARACTER` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: GUID of the main part.
- **MAINPART.WEIGHT** [10] `FLOAT` · ASSEMBLY, CAST_UNIT, DRAWING, REBAR_ASSEMBLY: Weight of the main part alone (not the assembly).
- **PROFILE.WIDTH** [41] `FLOAT` · PART: Catalog width of the part's profile.
- **PROFILE.HEIGHT** [26] `FLOAT` · PART: Catalog height of the part's profile.
- **ASSEMBLY.ASSEMBLY_POS** [113] `CHARACTER` · BOLT, DRAWING, PART: From a part/bolt row: mark of the containing assembly.
- **ASSEMBLY.MODEL_TOTAL** [79] `INTEGER` · BOLT, DRAWING, PART: From a part row: how many of the containing assembly exist in the model.
- **ASSEMBLY.HIERARCHY_LEVEL** [65] `INTEGER` · DRAWING, PART: From a part row: nesting level of its assembly.
- **ASSEMBLY.ASSEMBLY_POSITION_CODE** [33] `CHARACTER` · BOLT, DRAWING, PART: From a part row: grid code of its assembly.
- **ASSEMBLY.GUID** [11] `CHARACTER` · BOLT, DRAWING, PART: From a part row: GUID of its assembly.
- **ASSEMBLY.WEIGHT** [11] `FLOAT` · DRAWING, PART: From a part row: weight of the whole assembly.
- **ASSEMBLY.MAINPART.NAME** [11] `CHARACTER` · PART: From a part row: name of its assembly's main part.
- **ASSEMBLY.MAINPART.PROFILE** [11] `CHARACTER` · PART: From a part row: profile of its assembly's main part.
- **CAST_UNIT.MODEL_TOTAL** [22] `INTEGER` · ASSEMBLY, PART, REBAR_ASSEMBLY, SURFACING: From a part/rebar row: how many of its cast unit exist in the model.
- **POUR_OBJECT.POUR_NUMBER** [25] `CHARACTER` · POUR_UNIT: On POUR_UNIT: pour number of its pour object (unverified).
- **POUR_OBJECT.MATERIAL** [13] `CHARACTER` · POUR_UNIT: On POUR_UNIT: concrete grade of its pour object.
- **POUR_OBJECT.POUR_TYPE** [13] `CHARACTER` · POUR_UNIT: On POUR_UNIT: pour type of its pour object (unverified).
