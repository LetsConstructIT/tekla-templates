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
repo** — regenerate them once against the Tekla version you use. Run from the skill folder:

```powershell
# 1. Grammar allow-list  -> assets/template-grammar.json   (used by -Strict validation)
scripts\Get-TeklaGrammar.ps1            # add -TeklaRoot C:\TeklaStructures\<version> to pin a version

# 2. JSON schema         -> assets/template-schema.json    (pure function of the grammar; already
#                                                            shipped, regenerate only if you rebuild grammar)
scripts\New-TeklaTemplateSchema.ps1

# 3. Corpus index        -> assets/template-index.json     (used by Find-TeklaTemplateExamples.ps1)
scripts\Get-TeklaTemplateIndex.ps1
```

If you omit `-TeklaRoot`, the scripts auto-detect the newest installed version. Both sweep the
whole shipped corpus (2,688 files / 128 MB): the grammar takes ~30 s and the index ~65 s, and
they only need doing once per Tekla version. Until these files exist, the dependent features degrade gracefully — the scripts
tell you exactly which one to run — and everything else works normally.

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
