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

### Changed
- `SKILL.md`: description mentions Excel/CSV output; skeleton table separates CSV export
  from formatted Excel reports; new "Excel reports are a separate pipeline" section.
- `assets/template-schema.json` regenerated from the latest grammar harvest.

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
