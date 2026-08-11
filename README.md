# criticmarkup.nvim

A small Neovim plugin for editing documents annotated with
[CriticMarkup](https://github.com/CriticMarkup/CriticMarkup-toolkit):

```
Addition:     {++inserted text++}
Deletion:     {--removed text--}
Substitution: {~~old~>new~~}
Comment:      {>>a remark<<}
Highlight:    {==marked text==}
```

Features:

- Highlights annotations using extmarks, so it works alongside treesitter
  (no `syntax on`, no regex syntax engine).
- Accept or reject the annotation under the cursor, or all annotations in a
  visual selection / command range. Annotations may span lines.
- Jump between annotations.
- Operators and visual mappings for creating annotations.
- Optional concealment for non-standard leading paragraph blocks such as
  `[s: draft]` and `[s*: important]`.

Requires Neovim ≥ 0.9.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "wilenius/criticmarkup.nvim",
  ft = { "markdown", "pandoc", "text" },
  opts = {},
}
```

## Usage

`:CriticMarkup accept` and `:CriticMarkup reject` resolve the annotation
under the cursor. With a range (e.g. a visual selection), they resolve every
annotation in the range. Accepting keeps additions, applies substitutions and
drops deletions; rejecting does the opposite. Comments are removed by either
action, and highlights keep their text (only the markup is stripped).

Default mappings (buffer-local, in attached buffers):

| Mapping           | Mode | Action                              |
| ----------------- | ---- | ----------------------------------- |
| `<LocalLeader>ca` | n, x | Accept annotation(s)                |
| `<LocalLeader>cr` | n, x | Reject annotation(s)                |
| `]m` / `[m`       | n    | Next / previous annotation          |
| `<LocalLeader>ea` | n, x | Add addition (operator / selection) |
| `<LocalLeader>ed` | n, x | Add deletion                        |
| `<LocalLeader>es` | n, x | Add substitution                    |
| `<LocalLeader>ec` | n, x | Add comment                         |
| `<LocalLeader>eh` | n, x | Add highlight                       |

The creation mappings are operators in normal mode (`<LocalLeader>ediw`
deletes the inner word, CriticMarkup-style). After adding a substitution the
cursor is placed before `~~}`, ready for `i` and the replacement text.

## Configuration

Defaults:

```lua
require("criticmarkup").setup({
  highlight = true,
  -- Conceal markup delimiters; only takes effect when 'conceallevel' > 0.
  conceal = true,
  filetypes = { "markdown", "pandoc", "text" },
  default_mappings = true,
  -- Opt in to non-standard [s: ...] and [s*: ...] paragraph blocks.
  paragraph_blocks = false,
})
```

When `paragraph_blocks` is enabled, consecutive `[s: ...]` and `[s*: ...]`
blocks at the start of a paragraph are concealed. In Insert or Replace mode,
they are shown only while the cursor is within that paragraph. Paragraphs are
separated by blank lines. Other bracketed forms, including `[note: ...]`, are
left untouched. Like delimiter concealment, this respects Neovim's
`conceallevel` and `concealcursor` options.

With `default_mappings = false`, map the Lua API yourself:
`accept()`, `reject()`, `accept_range(l1, l2)`, `reject_range(l1, l2)`,
`next()`, `prev()`, `annotate(kind)` (expression mapping, returns `g@`) and
`annotate_visual(kind)`, where `kind` is one of `addition`, `deletion`,
`substitution`, `comment`, `highlight`. Buffers with other filetypes can be
attached manually with `require("criticmarkup").attach()`.

Highlight groups (all overridable): `CriticAddition` → `DiffAdd`,
`CriticDeletion` → `DiffDelete`, `CriticHighlight` → `DiffText`,
`CriticComment` → `Comment`, `CriticMarker` → `Delimiter`. One more,
`CriticIgnore`, carries no colour: it is `nocombine`, and is used to keep the
replacement half of a substitution from inheriting the strikethrough that
markdown reads its `~~` delimiters as.

## Tests

```
make test
```

(runs [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) busted specs
headlessly).
