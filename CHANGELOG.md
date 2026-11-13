# Changelog

All notable changes to this skill are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Formatted Excel report pipeline (HTML + Excel `mso-` CSS inside `*.xls.rpt`):
  - `scripts/New-TeklaXlsReport.ps1` generates a complete template from a column spec,
    handling balanced cells/rows, Excel Text format on text columns, `replace()`
    HTML-escaping of model text, and a large `maxheight`.
  - `scripts/Test-TeklaHtmlReport.ps1` lints the HTML document a template produces
    (tag balance, per-band balance, cell counts, Text format, escaping, `maxheight`).
  - `tests/Test-TeklaHtmlReportLint.ps1` regression suite for the generator and lint.
  - `assets/skeleton_xls_report.xls.rpt` skeleton with preview SVG.
- `xls-html` feature tag in `Get-TeklaTemplateIndex.ps1` / `Find-TeklaTemplateExamples.ps1`.
- "Formatted Excel report" section in `references/recipes.md`.
- Attribute definitions (meanings, not just names), built locally from the user's own copy of
  Trimble's "Template attributes" PDF; Trimble's text, so gitignored and never shipped:
  - `scripts/Get-TeklaAttributeDefinitions.ps1` writes `references/attribute-definitions.md`,
    one grep-able line per attribute with § and page, checked against the PDF's TOC
    (2025: 475 sections, 2026: 480). Uses the `pdftotext` bundled with Git for Windows.
  - `Initialize-TeklaTemplates.ps1 -AttributePdf`, plus auto-pickup of `TS_TEA_*` PDFs from
    the skill folder / Downloads, preferring the installed Tekla year; optional, never
    affects readiness.
- Weld rows and the intermittent-weld trap in `references/attribute-cookbook.md`.
- `references/attribute-glossary.md`: hand-written meanings (in our own words) of the 300
  attributes most used across the 2,685 shipped 2026.0 templates, with catalog type/unit,
  content types and usage counts; meanings not confirmed by Trimble's PDF or a shipped label
  are marked *(unverified)*. Shipped, so meanings work without the PDF.

### Changed
- `SKILL.md`: description mentions Excel/CSV output; skeleton table separates CSV export
  from formatted Excel reports; new "Excel reports are a separate pipeline" section.
- `assets/template-schema.json` regenerated from the latest grammar harvest.
- `SKILL.md`: "a valid name is not a known meaning" rule. Claude looks a meaning up in the
  definitions file and cites it, or labels it unverified. Previously it presented label-based
  guesses as fact (`WELD_ACTUAL_LENGTH1` read as "welded length without gaps").
- Cookbook: the bare-`WEIGHT` trap now states the documented rule (gross for catalog
  cross-sections, net for parametric profiles); new `VOLUME`-is-mm³-in-arithmetic trap.

## 2026-08-11
### Changed
- Shortened the skill description to under 1024 characters.

## 2026-08-09
### Added
- `scripts/Initialize-TeklaTemplates.ps1` to simplify the first run of the skill.
- Compiled C# fast path for the template tokenizer in `_TemplateParser.ps1`.

### Changed
- README updates.

### Initial public release
- Skill, references, skeleton templates and scripts.
