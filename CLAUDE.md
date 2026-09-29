# my-vim-org-mode

Org-mode for Vim in plain VimScript (no Neovim-only APIs). The reference for
behaviour is Emacs org-mode with default settings: when in doubt, match what
Emacs writes into the file, so notes stay compatible with Doom/Emacs.

## Validate every change

```sh
tests/run.sh                    # whole Vader suite, headless, ~1.5 s
tests/run.sh tests/todo.vader   # one module
```

- Every behaviour change or bug fix comes with a Vader case in `tests/<module>.vader`.
  Write the failing case first when fixing a bug.
- Timestamps in expectations are built with `tests/helpers.vim` (`Now()`,
  `Ymd(offset)`, `Date(y, m, d)`) so they hold on any day and locale. `SFunc(file,
  name)` reaches a script-local function when the only entry point is interactive
  (the calendar popup).
- Run the suite with `LC_ALL=C` too when touching dates or day names.

## Vader gotchas (each one cost time)

- `Before:` runs before **every** `Execute`/`Do` block, not once per case: put setup
  and the action in the same `Execute`, feeding prompt answers with
  `feedkeys("text\<CR>", 't')`.
- Never `%bwipeout!` in `After:`; it kills Vader's own buffers and Vim quits.
  Wipe only the test's buffers.
- In `Do:` blocks `<Esc>` on the command line acts like `<CR>` (`:normal`).
- `Given` strips the common indent of its lines.
- A Funcref variable name must start with a capital (`let F = SFunc(...)`).
- The runner fails if Vader's summary is missing: a prompt (`-- More --`, swap,
  "file changed") reads EOF and Vim quits; `tests/vimrc` sets `nomore`,
  `noswapfile`, `autoread` for that reason.

## Plugin conventions

- Shared helpers live in `autoload/org/core.vim`; reuse them instead of new regexes:
  `keywords()` (with `#+SEQ_TODO` shortcuts and `!`/`@` log specs), `scan_header`,
  `set_property` (Emacs `%-10s %s` spacing), `ensure_logbook`, `log_item`,
  `file_entry` / `set_level` (file a subtree under a heading), `headline_title`,
  `tags_pattern` / `tag_char` (non-ASCII tags like `:VEHÍCULOS:`), `dow` / `fix_dow`.
- A headline is `^\*\+\s`, never bare `^\*` (`*bold*` at line start is text).
- Dates: compute with JDN (`org#core#jdn`) and anchor epochs at noon, or use pure
  day-number mappings. Midnight-based epochs shift a day across Chile's DST change.
- Day names come from `strftime('%a')` in the user's locale (`mié`, `sáb`), never
  hard-coded.
- Pad or measure user text with `strdisplaywidth()`, not `len()`/`printf('%-*s')`.
- `v:count` has the bare alias `count`: never name a variable `count`.
- Open files with `hide edit` so a buffer with unsaved changes does not raise E37.
- `README.md` documents every mapping, option and file format; update it in the
  same commit as the behaviour.

## Repo workflow

- After pushing, update the installed copy: `git -C ~/.vim/plugged/my-vim-org-mode
  pull --ff-only`.
- Git has no global identity on this machine: commit with
  `git -c user.name='Claudio Olivares' -c user.email=claudio.pol.olivares@gmail.com`.
- A hook blocks any command containing both `push` and `-F`: run commit and push as
  separate commands.
