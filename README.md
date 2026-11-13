# tekla-templates

A [Claude Code](https://claude.com/claude-code) **skill** for authoring, generating, editing,
and debugging Tekla Structures Template Editor templates — the `.rpt` files behind reports
(part / assembly / bolt / material lists, bills of material) and the `.tpl` files behind
drawing tables (title blocks, revision tables, drawing lists).

It lets Claude read, generate, and edit template text directly — a JSON IR pipeline with a
deterministic emitter, grammar/attribute validation (`-Strict`), an SVG preview renderer, a
searchable index of the shipped template corpus, and install helpers. The Template Editor GUI
is not required.

> Not affiliated with or endorsed by Trimble. Tekla and Tekla Structures are trademarks of
> Trimble Inc.

## Requirements

- **Claude Code** — the primary target, and what the install steps below assume. Other
  coding agents work too; see [Use with other agents](#use-with-other-agents).
- **Windows + PowerShell** (the `scripts/*.ps1` are PowerShell)
- **Tekla Structures** installed — needed only to (re)generate the local data assets and to
  install templates into an environment; template authoring/editing itself does not need it.

## Install

Clone into your Claude Code skills directory so the folder lands at
`~/.claude/skills/tekla-templates`:

```bash
git clone https://github.com/LetsConstructIT/tekla-templates.git ~/.claude/skills/tekla-templates
```

On Windows PowerShell:

```powershell
git clone https://github.com/LetsConstructIT/tekla-templates.git "$HOME\.claude\skills\tekla-templates"
```

Restart Claude Code (or start a new session) and the `tekla-templates` skill is available.

Then ask Claude, in the chat:

> Prepare tekla-templates to work

That runs the one-time setup below for you (~2 minutes) and reports which Tekla version it
built against. Nothing else to do.

## Use with other agents

Very little here is Claude Code-specific. `SKILL.md` and everything in `references/` is plain
markdown; `scripts/` is PowerShell invoked through a shell. Any agent that can read files in a
folder and run shell commands can use this — clone the repo anywhere and point the agent at
`SKILL.md` (paste it, add it to the agent's instruction/rules file, or let the agent open it).

Only the discovery mechanics are Claude Code's: the `~/.claude/skills/<name>/` location, the
`/tekla-templates` command, and automatic loading based on the YAML `description` in
`SKILL.md`'s frontmatter. Elsewhere you supply that context yourself.

One thing to carry over: every `scripts\…` path in `SKILL.md` is relative to the skill folder,
not the working directory. Tell the agent where it cloned the repo, or it will look in the
wrong place.

## First-time setup (one-time, per Tekla version)

Two data assets are **derived from your local Tekla install and are not shipped in this
repo**, so they're built once on your machine. Easiest route is to ask Claude —
*"prepare tekla-templates to work"* — which runs exactly the script below.

To do it yourself, from the skill folder:

```powershell
scripts\Initialize-TeklaTemplates.ps1           # builds whatever is missing
scripts\Initialize-TeklaTemplates.ps1 -Check    # status only (exit 0 = ready, 1 = setup needed)
scripts\Initialize-TeklaTemplates.ps1 -Force    # rebuild, e.g. after upgrading Tekla
```

It auto-detects the newest installed version; `-TeklaRoot C:\TeklaStructures\<version>` pins
one, and `-Path <folder>` folds in a firm/project library (or stands in for a missing local
install). Re-running is safe — assets that are already current are skipped.

| Built | File | Used by |
|---|---|---|
| Grammar allow-list | `assets/template-grammar.json` | `-Strict` validation |
| JSON schema | `assets/template-schema.json` | JSON-IR schema gate (pure function of the grammar) |
| Corpus index | `assets/template-index.json` | `Find-TeklaTemplateExamples.ps1` |

The grammar and index each sweep the whole shipped corpus (2,688 files / 128 MB) — ~30 s and
~65 s, once per Tekla version. Until they exist the dependent features degrade gracefully —
each script tells you which one to run — and everything else works normally.

### Optional (recommended): attribute definitions

The skill ships `references/attribute-glossary.md`, our own descriptions of the 300 most-used
attributes. For the rest, Claude would infer meanings from names and labels, and those can
mislead. For example, `WELD_ACTUAL_LENGTH1` includes the gaps of an intermittent weld. To give
Claude Trimble's full definitions of every documented attribute:

1. Download the *"Template attributes in drawing and report templates"* PDF for your Tekla
   version and language from Tekla User Assistance, e.g. `TS_TEA_2026_en_Template_attributes.pdf`.
2. Put it in your Downloads folder or the skill folder and re-run setup, or pass it explicitly:

```powershell
scripts\Initialize-TeklaTemplates.ps1 -AttributePdf "$HOME\Downloads\TS_TEA_2026_en_Template_attributes.pdf"
```

This writes `references/attribute-definitions.md` (~1 s). It has one line per attribute and is
checked against the PDF's table of contents. Claude searches it before saying what an
attribute means, and flags meanings as unverified when it's missing. Text extraction uses
`pdftotext`, which ships with Git for Windows. The file is Trimble's text, so it is gitignored:
build your own and don't redistribute it.

## Why those two files aren't in the repo

`template-grammar.json` and `template-index.json` are harvested by scanning Trimble/Tekla's
proprietary shipped `.tpl` / `.rpt` files. Rather than redistribute data derived from those
files, each user regenerates them from the Tekla installation they already license. See
[`.gitignore`](.gitignore).

## What's in here

| Path | What it is |
|------|-----------|
| `SKILL.md` | The skill instructions Claude reads |
| `scripts/` | PowerShell: grammar/index/schema generators, JSON-IR convert, preview renderer, validator, installer |
| `tests/` | Development-only regression suite (round-trip losslessness proof over the shipped corpus) |
| `references/` | Attribute cookbook, functions, formulas, file format, recipes, debugging |
| `assets/skeleton_*` | Authored starter templates + SVG previews |
| `assets/template-schema.json` | JSON Schema for the template IR (shipped) |

## License

[MIT](LICENSE) © Grzegorz Olszewski. Covers the scripts, docs, and authored templates in this
repository. The locally generated data assets are derived from your own Tekla installation and
are outside this repository.
