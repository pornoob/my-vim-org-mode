# vim-org

A VimScript plugin for working with [Org Mode](https://orgmode.org/) files (`.org`) in Vim.

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
  - [g:org\_leader](#gorg_leader)
  - [g:org\_todo\_keywords](#gorg_todo_keywords)
  - [g:org\_todo\_keyword\_faces](#gorg_todo_keyword_faces)
- [Key Mappings](#key-mappings)
- [TODO States](#todo-states)
  - [Sequential cycling](#sequential-cycling)
  - [Shortcut-key picker](#shortcut-key-picker)
  - [File-local keywords](#file-local-keywords)
  - [State-change logging](#state-change-logging)
  - [Repeating tasks on DONE](#repeating-tasks-on-done)
- [Context Action](#context-action)
- [Clocking](#clocking)
  - [Clock report](#clock-report)
- [Agenda](#agenda)
- [Capture](#capture)
- [Scheduling and Deadlines](#scheduling-and-deadlines)
  - [Calendar picker](#calendar-picker)
  - [Specific times](#specific-times)
  - [Text-prompt fallback](#text-prompt-fallback)
  - [Reschedule logging](#reschedule-logging)
- [Promote and Demote](#promote-and-demote)
- [Checkboxes](#checkboxes)
- [Commands](#commands)
- [Syntax Highlighting](#syntax-highlighting)
- [Code Blocks](#code-blocks)
- [Folding](#folding)
- [Keeping Your Config Safe](#keeping-your-config-safe)
- [File Layout](#file-layout)

---

## Installation

### vim-plug

```vim
call plug#begin()
Plug 'pornoob/my-vim-org-mode'       " from GitHub
" or during local development:
Plug 'E:/path/to/vim-org'
call plug#end()
```

Then run `:PlugInstall`.

### Vundle

```vim
Plugin 'pornoob/my-vim-org-mode'
" or local:
Plugin 'file:///E:/path/to/vim-org'
```

Then run `:PluginInstall`.

### Manual

```vim
set runtimepath+=E:/path/to/vim-org
```

---

## Quick Start

1. Install the plugin.
2. Open any `.org` file — syntax highlighting and folding activate automatically.
3. Press `\t` on a headline to cycle its TODO state.
4. Press `\s` to schedule the headline under the cursor (opens a calendar).
5. Press `\ci` to clock in, `\co` to clock out.
6. Run `:OrgReload` after changing any `g:org_*` variable to apply without restarting Vim.

---

## Configuration

All variables should be set in your `.vimrc` **before** `plug#end()`, or in your
[user config file](#keeping-your-config-safe).

### `g:org_leader`

The key prefix used for all org-mode mappings — only inside `.org` buffers.

| Priority | Source |
|---|---|
| 1 (highest) | `g:org_leader` |
| 2 | `maplocalleader` |
| 3 (default) | `\` (backslash) |

```vim
let g:org_leader = '\'        " default: \t \s \ci …
let g:org_leader = ','        " comma:   ,t ,s ,ci …
let g:org_leader = '<Space>'  " space:   <Space>t …
```

---

### `g:org_todo_keywords`

Defines the TODO state sequence and which states are _active_ vs _done_.

Two formats are accepted:

**Flat** (recommended) — use `|` to separate active from done:

```vim
let g:org_todo_keywords = ['TODO', 'NEXT', 'WAITING', '|', 'DONE', 'CANCELLED']
```

**Nested** — a list of two lists:

```vim
let g:org_todo_keywords = [['TODO', 'NEXT', 'WAITING'], ['DONE', 'CANCELLED']]
```

- States **before** `|` are active/pending — highlighted in warm bold colours.
- States **after** `|` are done/finished — highlighted in muted colours.
- Cycling order: _(no state)_ → active states → done states → _(no state)_.

---

### `g:org_todo_keyword_faces`

A dictionary that maps keyword strings to highlight specifications.

```vim
let g:org_todo_keyword_faces = {
  \ 'TODO':      'ctermfg=167 cterm=bold   guifg=#fb4934 gui=bold',
  \ 'NEXT':      'ctermfg=208 cterm=bold   guifg=#fe8019 gui=bold',
  \ 'WAITING':   'ctermfg=214 cterm=bold   guifg=#fabd2f gui=bold',
  \ 'DONE':      'ctermfg=142 cterm=italic guifg=#b8bb26 gui=italic',
  \ 'CANCELLED': 'ctermfg=245 cterm=NONE   guifg=#928374 gui=strikethrough',
  \ }
```

Each keyword gets its own highlight group `orgKw_{KEYWORD}` that you can override:

```vim
highlight orgKw_TODO ctermfg=196 cterm=bold guifg=#ff0000 gui=bold
```

---

## Key Mappings

All mappings are **buffer-local** (only active in `.org` files) and use the
[`g:org_leader`](#gorg_leader) prefix (default `\`).

| Mapping | Mode | Action |
|---|---|---|
| `{leader}t` | Normal | Cycle TODO state forward |
| `{leader}T` | Normal | Cycle TODO state backward |
| `{leader}a` | Normal | Open agenda |
| `{leader}s` | Normal | Set/update SCHEDULED date |
| `{leader}d` | Normal | Set/update DEADLINE date |
| `{leader}ci` | Normal | Clock in on current headline |
| `{leader}co` | Normal | Clock out (close open clock) |
| `{leader}cc` | Normal | Toggle clock in/out |
| `{leader}cr` | Normal | Insert or update clock report at cursor |
| `{leader}<` | Normal | Promote headline subtree |
| `{leader}>` | Normal | Demote headline subtree |
| `{leader}<` | Visual | Promote all headlines in selection |
| `{leader}>` | Visual | Demote all headlines in selection |
| `{leader}R` | Normal | Reload org config (`:OrgReload`) |
| `{leader}x` | Normal | Toggle checkbox `[ ]` → `[X]` → `[-]` → `[ ]` |
| `{leader}x` | Visual | Toggle all checkboxes in selection |
| `{leader}o` | Normal | Open link under cursor (`[[url]]`, `[[file:path]]`, `[[id:uuid]]`) |
| `<CR>` | Normal | Open link under cursor (same as `{leader}o`) |
| `{leader},` | Normal | Cycle priority `[#A]` → `[#B]` → `[#C]` → _(none)_ |
| `{leader};` | Normal | Cycle priority backward |
| `{leader}:` | Normal | Edit tags on current headline (comma-separated, with completion; any letter works, `:VEHÍCULOS:` included; an empty answer cancels, so delete the last tags by hand) |
| `{leader}i` | Normal | Generate and insert `:ID:` property |
| `{leader}$` | Normal | Archive subtree to `*.org_archive` |
| `{leader}C` | Normal / Visual | **Global** — open capture template (works from any filetype; uses `g:org_leader` or `\`, never `maplocalleader`). In visual mode the selection fills `%i` |
| `<C-c><C-c>` | Normal | [Context action](#context-action) — update whatever is under the cursor |
| `{leader}f` | Normal | Toggle all folds: open all if any closed, close all if all open |
| `<Tab>` | Normal | Toggle fold on headline |
| `<S-Tab>` | Normal | Cycle global fold: OVERVIEW → CONTENTS → SHOW ALL |

---

## TODO States

### Sequential cycling

Without shortcut keys, `{leader}t` steps through the state sequence one at a time:

```
(none) → TODO → NEXT → WAITING → DONE → CANCELLED → (none) → …
```

`{leader}T` cycles backward.

When a headline enters a **done** state, a `CLOSED:` timestamp is automatically inserted:

```org
* DONE Write README
  CLOSED: [2026-07-09 Wed 10:30]
```

### Shortcut-key picker

When your keyword list includes shortcut keys (see below), pressing `{leader}t`
shows an inline prompt instead of stepping:

```
State (t:TODO  w:WAITING  d:DONE  SPC:clear):
```

Press the single key to jump directly to that state, or `<Space>` to clear.

### File-local keywords

Add a `#+SEQ_TODO:` line at the top of your file to override the global keyword list
for that file only:

```org
#+SEQ_TODO: TODO(t) WAITING(w) REVIEW(r) | DONE(d) PAYED(p) CANCELLED(c)
```

- Keywords with `(key)` get shortcut keys and trigger the picker.
- Keywords without parentheses use sequential cycling.
- The `|` separator marks the done/active boundary.
- Matching is case-insensitive (`#+seq_todo:` works).
- `#+TODO:` is accepted as a synonym of `#+SEQ_TODO:`.
- Emacs logging specs are understood: `DONE(d@/!)` keeps `d` as the shortcut,
  `WAIT(@/!)` has no shortcut, and the `@` / `!` markers turn on
  [state-change logging](#state-change-logging).

### State-change logging

The `!` and `@` markers in `#+SEQ_TODO:` log state changes into the headline's
`:LOGBOOK:` drawer, the way Emacs does with `org-log-into-drawer`:

| Marker | Effect |
|---|---|
| `DONE(d!)` | Entering `DONE` logs a timestamp |
| `DONE(d@)` | Entering `DONE` logs a timestamp and prompts for a one-line note |
| `WAIT(w@/!)` | Note when entering `WAIT`, timestamp when leaving it |

The marker of the state being entered wins; when it has none, the leaving marker
of the old state applies. An empty note (or `<Esc>`) logs just the timestamp.

```org
#+SEQ_TODO: TODO(t) WAIT(w@/!) | DONE(d@)
* DONE Pay the bill
  CLOSED: [2026-09-29 Tue 18:34]
  :LOGBOOK:
  - State "DONE"       from "TODO"       [2026-09-29 Tue 18:34] \\
    Paid in cash
  :END:
```

- The newest item goes on top. An existing drawer is reused with its indentation;
  a new one is placed after the planning lines and `:PROPERTIES:`.
- Files without markers (and the global `g:org_todo_keywords`) log nothing, except
  for repeating tasks (below).

### Repeating tasks on DONE

When a headline whose `SCHEDULED` or `DEADLINE` carries a repeater is moved to a
**done** state, the plugin does not close it. Instead it shifts the date forward
and puts the headline back to the first active keyword — no `CLOSED:` line is added.

```org
* TODO Pay rent
  SCHEDULED: <2026-07-01 Wed +1m>
```

After `{leader}t` → `DONE`:

```org
* TODO Pay rent
  SCHEDULED: <2026-08-01 Sat +1m>
  :PROPERTIES:
  :LAST_REPEAT: [2026-07-01 Wed 09:12]
  :END:
  :LOGBOOK:
  - State "DONE"       from "TODO"       [2026-07-01 Wed 09:12]
  :END:
```

Like Emacs' `org-log-repeat`, every repeat is logged and stamped with
`:LAST_REPEAT:`, with or without markers in `#+SEQ_TODO:`. `g:org_log_repeat`
controls it:

| Value | Effect |
|---|---|
| `'time'` (default) | State line with a timestamp, plus `:LAST_REPEAT:` |
| `'note'` | Same, and prompts for a note |
| `''` | Nothing (a `@` marker on the done state still asks for a note) |

| Repeater | Next date |
|---|---|
| `+1m` | Old date + one interval (may still be in the past) |
| `++1w` | Old date + as many intervals as needed to land after today (keeps the weekday) |
| `.+1d` | Today + one interval |

- Supported units: `d`, `w`, `m`, `y`. Month steps clamp to the month's last day
  (`Jan 31 +1m` → `Feb 28`).
- Only the date and day name change: the time, the repeater and a warning delay
  (`<2026-09-20 Sun +1w -2d>`) are kept.
- Every repeating stamp in the planning lines moves, so `DEADLINE: <…> SCHEDULED: <…>`
  on one line are both shifted.

---

## Context Action

`<C-c><C-c>` (or `:OrgCtrlC`) mirrors Emacs org-mode's `C-c C-c`: it looks at the
line under the cursor and does whatever update makes sense there.

| Cursor on | Action |
|---|---|
| Closed `CLOCK:` line (`[…]--[…]`) | Recalculate its `=>` duration |
| Open (running) `CLOCK:` line | Clock out |
| Checkbox list item | Toggle it and refresh parent `[n/m]` / `[%]` summaries |
| `#+BEGIN: clocktable` block (or inside it) | Regenerate the clock report |
| Line with a `[[link]]` | Open the link |
| Any other line with a timestamp | Fix a stale day name (e.g. `<2026-07-09 Mon>` → `<2026-07-09 Thu>`) |

---

## Clocking

Track time spent on tasks using the `:LOGBOOK:` drawer.

### Clock in

Place the cursor on (or under) a headline and press `{leader}ci`:

```org
* TODO Write plugin docs
  :LOGBOOK:
  CLOCK: [2026-07-09 Wed 09:00]
  :END:
```

- If another clock is already running anywhere in the buffer, it is closed first.
- A `:LOGBOOK:` drawer is created automatically if none exists.

### Clock out

Press `{leader}co` to close the open clock. Duration is computed and appended:

```org
  CLOCK: [2026-07-09 Wed 09:00]--[2026-07-09 Wed 10:45] =>  1:45
```

The duration is written as Emacs does (`%2d:%02d`): `=>  1:45`, `=> 10:30`.
A new `CLOCK:` line is indented like its `:LOGBOOK:` drawer.

### Toggle

`{leader}cc` clocks in when no clock is running, or clocks out if one is open.

### Recalculate durations

After editing a `CLOCK:` line by hand, its `=>` duration goes stale:

- `<C-c><C-c>` or `:OrgClockUpdate` on the line recalculates that entry.
- `:OrgClockUpdateAll` recalculates every closed entry in the buffer.

### Clock report

Press `{leader}cr` (or `:OrgClockReport`) to insert a clock summary table at the
cursor. If the cursor is already inside a `#+BEGIN: clocktable` block, the block is
regenerated in place instead.

```org
#+BEGIN: clocktable :scope file :maxlevel 3 :block thisweek
#+CAPTION: Clock summary at [2026-07-21 Tue 10:30]
| Headline             |    Time |
|----------------------+---------|
| *Total*              |  *5:45* |
|----------------------+---------|
| Project Alpha        |    3:00 |
| \_  Design           |    1:30 |
| \_  Implementation   |    1:30 |
| Project Beta         |    2:45 |
#+END:
```

Parameters on the `#+BEGIN:` line:

| Parameter | Values | Default |
|---|---|---|
| `:scope` | `file`, `subtree` | `file` |
| `:maxlevel` | integer | `3` |
| `:block` | `today`, `thisweek`, `lastweek`, `thismonth`, `lastmonth` | all time |
| `:tstart` | `[YYYY-MM-DD ...]` | unbounded |
| `:tend` | `[YYYY-MM-DD ...]` | unbounded |

An open clock (no end time) is counted up to the current moment.

---

## Agenda

Press `{leader}a` (or `:OrgAgenda`) to open the agenda in a horizontal split.

### Configuration

```vim
" Files to scan (default: current buffer when filetype=org).
" Each entry can be an individual .org file or a directory.
" Directories are scanned recursively — all *.org files at any depth are included.
let g:org_agenda_files = [
  \ 'E:\org',            " directory: finds E:\org\**\*.org recursively
  \ '~/notes/inbox.org', " individual file
  \ ]

let g:org_agenda_deadline_days  = 14  " deadline horizon (days)
let g:org_agenda_window_height  = 20  " split height
let g:org_agenda_day_start      = 7   " earliest hour in Day view
let g:org_agenda_day_end        = 22  " latest hour in Day view
let g:org_agenda_show_past_scheduled = 1  " missed SCHEDULED items nag on today (0 = off)
```

### Views

| Key | View | Description |
|---|---|---|
| `W` | Week | 7-day grid with scheduled items and deadlines per day |
| `A` | Day | Hourly timeline for a single day |
| `M` | Month | Calendar grid + item list for the focused day |
| `T` | Todos | All active TODO headlines, grouped by state |
| `D` | Deadlines | Upcoming deadlines within the configured horizon |

### Navigation

| Key | Action |
|---|---|
| `n` | Next week / next day / next month |
| `p` | Previous week / previous day / previous month |
| `.` | Jump back to today |
| `h` / `l` | Move focused day left/right by one day (Month view) |
| `j` / `k` | Move focused day down/up by one week (Month view) |
| `Enter` | Open source file at the item's line |
| `o` | Preview source in other window (stay in agenda) |
| `{leader}t` / `{leader}T` | Cycle the item's TODO state forward / backward (saves the file and refreshes) |
| `r` / `g` | Refresh (re-scan all files) |
| `q` | Close agenda |

### Repeating tasks

Tasks with a repeat interval (`+1w`, `+1d`, `.+1m`, etc.) appear on every future
occurrence in the Week and Day views. When a task is showing on a repeated occurrence
(past its original base date), the time slot displays how many days it has been
outstanding — e.g. `28d` in red — instead of a clock time. This makes it easy to
spot habits or recurring tasks that haven't been attended to in a while.

The Month view only shows items on their base date and does not list repeated
occurrences, keeping the calendar uncluttered.

### Missed scheduled items

As in Emacs org-agenda, a `SCHEDULED` item that is still in an active TODO state
keeps showing on **today** after its date (or its latest repeat occurrence) has
passed, labelled `Sched.Nx` — N days since the missed occurrence:

```
 Tuesday   Jul 14 ◀ today
   Sched.3x         TODO  Weekly review               work.org:40
```

- Shown in the Week view (on today's row, when today is in the displayed week)
  and in the Day view for today.
- In the week containing today, the earlier missed occurrences are suppressed so
  the item is listed once, not twice.
- Items without a TODO keyword, or already done, never nag.
- Turn it off with `let g:org_agenda_show_past_scheduled = 0` — a repeating task
  is then listed only on its exact occurrence dates.

### TODO view sorting

Items in the TODO view are grouped by state and sorted by priority within each
group (`[#A]` first, then `[#B]`, `[#C]`, unprioritised last).

### Week view example

```
 Org Agenda — Week  Mon Jul 13 – Sun Jul 19  ·  W29
 W week  A day  M month  T todos  D deadlines    n/p next/prev  . today  q quit
 ───────────────────────────────────────────────────────────────────────
 Overdue:
   Deadline  3 days ago  WAITING  Old report         notes.org:31
 ───────────────────────────────────────────────────────────────────────
 Monday    Jul 13
   (nothing scheduled)
 Tuesday   Jul 14 ◀ today
   Scheduled  09:00  NEXT  Write README              work.org:72
   Deadline         TODO  Submit invoice             billing.org:12
 Wednesday Jul 15
   (nothing scheduled)
 ...
```

### Day view example

```
 Org Agenda — Day  Tuesday 14 July 2026 ◀ today  ·  W29
 ───────────────────────────────────────────────────────────────────────
 All day:
   Deadline   TODO  Submit invoice                   billing.org:12

  7:00 ──────────────────────────────────────────────────────────────
  8:00 ──────────────────────────────────────────────────────────────
  9:00  Scheduled  09:00  NEXT  Write README          work.org:72
 10:00 ◀ now ──────────────────────────────────────────────────────
 11:00 ──────────────────────────────────────────────────────────────
```

---

## Capture

`{leader}C` (or `:OrgCapture`) opens a scratch buffer pre-filled from a template,
from any filetype. With one template it opens directly; with several, a one-key
picker is shown (`q` / `Esc` cancels). In visual mode, `{leader}C` (or
`:'<,'>OrgCapture`) also hands the selection to the template's `%i`.

### Configuration

```vim
let g:org_capture_templates = [
  \ {'key': 't', 'desc': 'Task',
  \  'template': "* TODO %?\n  %t",
  \  'file': '~/org/inbox.org', 'headline': 'Inbox'},
  \ {'key': 'n', 'desc': 'Note from selection',
  \  'template': "* %?\n  %t  from [[file:%f]]\n\n%i",
  \  'file': '~/org/notes.org'},
  \ ]
```

| Field | Required | Meaning |
|---|---|---|
| `key` | yes | Single key in the picker |
| `desc` | yes | Label in the picker |
| `template` | yes | Text of the entry; use `\n` for new lines |
| `file` | yes | Target file (`~` and `$VARS` are expanded) |
| `headline` | no | Level-1 headline (`* Inbox`) to file the entry under |

### Template placeholders

| Placeholder | Expands to |
|---|---|
| `%T` | Active timestamp with time, `<2026-07-09 Wed 10:30>` |
| `%t` | Inactive timestamp with time, `[2026-07-09 Wed 10:30]` |
| `%f` | Full path of the buffer capture was started from |
| `%F` | File name only of that buffer |
| `%i` | The selection capture was started on (visual `{leader}C`); empty otherwise |
| `%?` | Cursor position after expansion (first occurrence only) |

### Finishing

| Key | Mode | Action |
|---|---|---|
| `<C-c><C-c>` | Normal / Insert | Write the entry to the target file and close |
| `<C-c><C-k>` | Normal / Insert | Discard and close |

Where the entry lands:

- With `headline` → as the **last child** of that level-1 headline, after its
  existing entries and their bodies. The entry's headlines are demoted so it sits
  one level below (`* TODO x` becomes `** TODO x`; sub-headlines keep their depth).
- With `headline` but the headline is missing (or the file does not exist yet) → the
  headline is created at the end of the file, as Emacs does.
- Without `headline` → appended at the end of the file, levels untouched.

---

## Scheduling and Deadlines

### Calendar picker

Press `{leader}s` (or `{leader}d` for DEADLINE) on a headline. A popup calendar
appears (requires Vim 8 with `popupwin`):

```
╭──────────────────────────────╮
│       July 2026              │
│ Mo  Tu  We  Th  Fr  Sa  Su  │
│                  1   2   3   │
│  4   5   6   7   8  [9] 10  │
│ 11  12  13  14  15  16  17  │
│ 18  19  20  21  22  23  24  │
│ 25  26  27  28  29  30  31  │
╰──────────────────────────────╯
```

Navigation:

| Key | Action |
|---|---|
| `h` / `←` | Previous day |
| `l` / `→` | Next day |
| `k` / `↑` | One week back |
| `j` / `↓` | One week forward |
| `n` | Next month |
| `p` / `N` | Previous month |
| `Enter` | Confirm date |
| `Esc` / `q` | Cancel |

### Specific times

After picking a date in the calendar (or entering one in the text prompt), you are
asked for an optional time:

```
Time (HH:MM or Enter to skip): 14:30
```

Entering a time produces a specific-time stamp:

```org
  SCHEDULED: <2026-07-09 Wed 14:30>
```

Pressing Enter without a time produces an all-day stamp:

```org
  SCHEDULED: <2026-07-09 Wed>
```

### Text-prompt fallback

When Vim does not support popup windows, a text prompt is used instead.
You can include an optional time in the same string:

```
SCHEDULED (YYYY-MM-DD [HH:MM]  today  +7d  +2w  +1m): today 14:30
```

Accepted date formats:

| Input | Meaning |
|---|---|
| `today` or `.` | Today |
| `tomorrow` | Tomorrow |
| `+N` or `+Nd` | N days from today |
| `+Nw` | N weeks from today |
| `+Nm` | N months from today (≈30 days each) |
| `YYYY-MM-DD` | Exact date |

### Reschedule logging

When you change an **existing** SCHEDULED or DEADLINE date, the previous date is
recorded in the headline's `:LOGBOOK:` drawer automatically:

```org
* TODO Pay invoice
  SCHEDULED: <2026-07-15 Wed>
  :LOGBOOK:
  - Rescheduled from "[2026-07-09 Wed]" on [2026-07-09 Wed 10:12]
  :END:
```

A `:LOGBOOK:` drawer is created if one does not already exist.
No note is written when a date is set for the first time.

---

## Checkboxes

Press `{leader}x` (or `:OrgCheckboxToggle`) on a line containing `[ ]`, `[X]`, or
`[-]` to cycle through the states:

```
[ ] → [X] → [-] → [ ] → …
```

Lines with `[]` (empty brackets) are also accepted and treated as unchecked.

### Visual mode

Select multiple lines in visual mode and press `{leader}x` to toggle all
checkboxes in the selection at once. Lines without a checkbox are skipped.

### Parent summary

When a checkbox is toggled, the plugin automatically updates the nearest ancestor
headline that carries a summary token — and then keeps walking up, updating every
further ancestor that has one too (cascading).

Two summary formats are supported; the format is detected from what is already on
the headline:

- `[n/m]` — count-based: `[2/5]` (done / total)
- `[%]` — percentage: `[40%]`

The summary must already exist on the headline — the plugin updates it but does not
insert one from scratch.

```org
* Shopping list [0/5]
  - [X] Milk
  - [ ] Eggs
  - [X] Bread
  - [ ] Butter
  - [X] Cheese
```

After toggling Eggs to `[X]`, the parent becomes `Shopping list [4/5]`.

### Headline checkbox auto-update

If the parent headline itself carries a checkbox (`[ ]`, `[X]`, or `[-]`), that
checkbox is also updated automatically to reflect the children's combined state:

| Children state | Headline checkbox |
|---|---|
| All done (`[X]`) | `[X]` |
| None done | `[ ]` |
| Mixed | `[-]` |

This cascades upward, so toggling a deeply-nested item can update multiple ancestor
headlines in one keystroke.

### Mixed states

Items marked `[-]` (indeterminate) are **not** counted as done in the summary.
Only `[X]` contributes to the done count:

```org
* Project [1/3]
  - [X] Write code
  - [-] Under review
  - [ ] Write tests
```

---

## Promote and Demote

### Normal mode — subtree

`{leader}<` and `{leader}>` operate on the entire **subtree** rooted at the
current headline (the headline plus all its children).

```org
** Parent           →  * Parent
*** Child           →  ** Child
```

Promoting a level-1 headline prints a warning and does nothing.

### Visual mode — selected lines only

Select one or more lines in visual mode, then press `{leader}<` or `{leader}>`.
Only headline lines (starting with `*`) in the selection are affected; body
content lines are left untouched.

---

## Commands

| Command | Description |
|---|---|
| `:OrgTodoCycle` | Cycle TODO state forward |
| `:OrgTodoCycleBack` | Cycle TODO state backward |
| `:OrgAgenda` | Open the agenda window |
| `:OrgSchedule` | Set/update SCHEDULED date |
| `:OrgDeadline` | Set/update DEADLINE date |
| `:OrgClockIn` | Clock in on current headline |
| `:OrgClockOut` | Clock out (close open clock) |
| `:OrgClockToggle` | Toggle clock in/out |
| `:OrgClockUpdate` | Recalculate the duration of the closed `CLOCK:` entry on the current line |
| `:OrgClockUpdateAll` | Recalculate every closed `CLOCK:` entry in the buffer |
| `:OrgClockReport` | Insert or update clock report (`#+BEGIN: clocktable`) at cursor |
| `:OrgCtrlC` | [Context action](#context-action) on the current line (`<C-c><C-c>`) |
| `:OrgOpenLink` | Open link under cursor |
| `:OrgPromote` | Promote headline subtree |
| `:OrgDemote` | Demote headline subtree |
| `:OrgCheckboxToggle` | Toggle checkbox on current line |
| `:OrgTags` | Edit tags on current headline |
| `:OrgSetID` | Generate and insert `:ID:` property on current headline |
| `:OrgArchive` | Archive current subtree to `*.org_archive` |
| `:OrgCapture` | Open capture template for quick entry |
| `:OrgReload` | Reload syntax and ftplugin for the current buffer, or refresh the agenda |

### `:OrgReload` in detail

Run this after editing any `g:org_*` variable at runtime, or after updating the plugin mid-session. Works from both an org buffer and the `[Org Agenda]` buffer.

**From an org buffer:**

1. Clears all syntax in the current buffer and removes the syntax guard.
2. Re-sources `syntax/org.vim` — picks up new keywords and colour faces.
3. Executes `b:undo_ftplugin` to cleanly remove all existing buffer mappings.
4. Re-sources `ftplugin/org.vim` — picks up a new `g:org_leader`.
5. Re-sources `plugin/org.vim` — re-registers all `:Org*` commands.
6. Re-sources every file in `autoload/org/` — picks up code changes without restarting Vim.

**From the agenda buffer:**

Skips the buffer-specific steps above and goes straight to re-sourcing commands and autoload modules, then calls `org#agenda#refresh()` to redraw the current view.

---

## Syntax Highlighting

| Element | Highlight group |
|---|---|
| Headlines level 1–8 | `orgHeadline1` … `orgHeadline8` |
| Headline stars | `orgStars1` … `orgStars8` |
| Active TODO keywords | `orgKw_{KEYWORD}` (warm bold, customisable) |
| Done TODO keywords | `orgKw_{KEYWORD}` (muted, customisable) |
| Priority `[#A]` | `orgPriority` |
| Tags `:foo:bar:` | `orgTag` |
| Active timestamp `<…>` | `orgTimestampActive` |
| Inactive timestamp `[…]` | `orgTimestampInactive` |
| SCHEDULED / DEADLINE / CLOSED | `orgPlanning` |
| `:PROPERTIES:` drawer | `orgProperties`, `orgPropertyKey` |
| `:LOGBOOK:` / CLOCK lines | `orgLogbook`, `orgClockLine`, `orgClockDuration` |
| `#+BEGIN_SRC` … `#+END_SRC` | `orgSrcBlock`, `orgBlockBound` |
| `#+BEGIN_EXAMPLE` block | `orgExampleBlock` |
| `#+BEGIN_QUOTE` block | `orgQuoteBlock` |
| `#+KEY:` metadata | `orgMetaKey` |
| `# comment` | `orgComment` |
| `[[link]]` / `[[link][desc]]` | `orgLink` |
| `*bold*` | `orgBold` |
| `/italic/` | `orgItalic` |
| `~code~` | `orgCode` |
| `=verbatim=` | `orgVerbatim` |
| `+strikethrough+` | `orgStrike` |
| List bullets `- / +` | `orgListBullet` |
| Numbered list `1. / 1)` | `orgListNum` |
| Checkbox `[ ]` | `orgCheckboxTodo` |
| Checkbox `[X]` | `orgCheckboxDone` |
| Checkbox `[-]` | `orgCheckboxIndet` |
| Checkbox summary `[n/m]` `[%]` | `orgCheckboxSummary` |
| Horizontal rule `-----` | `orgHRule` |

To override headline colours, add lines **after** `plug#end()`:

```vim
highlight orgHeadline1 ctermfg=167 cterm=bold guifg=#cc241d gui=bold
highlight orgHeadline2 ctermfg=214 cterm=bold guifg=#d79921 gui=bold
```

---

## Code Blocks

`#+BEGIN_SRC`, `#+BEGIN_EXAMPLE`, and `#+BEGIN_QUOTE` blocks get a distinct visual
treatment to stand out from surrounding prose:

- **Left border** — a `│` character (colored in the same teal as the delimiter
  lines) appears before every line in the block.
- **Embedded syntax** — `#+BEGIN_SRC python`, `#+BEGIN_SRC sh`, etc. automatically
  load the corresponding Vim syntax file for the language, so keywords, strings,
  and operators are highlighted correctly inside the block.

Supported language aliases include `bash`/`zsh`/`sh`, `py`/`python`, `js`/`ts`,
`rb`/`ruby`, `c++`/`cpp`, `yml`/`yaml`, `elisp`/`emacs-lisp`, and more. Any
language Vim has a built-in `syntax/` file for will work.

Blocks are **foldable** — press `<Tab>` on a `#+BEGIN_SRC` line to collapse the
block to a single fold line showing the language and line count.

---

## Folding

Folding uses `foldmethod=expr`. Three kinds of structures create folds:

| Structure | Fold trigger |
|---|---|
| Headlines (`*`, `**`, …) | Each level creates a nested fold |
| Source / example / quote blocks | `#+BEGIN_*` … `#+END_*` |
| Drawers | `:PROPERTIES:` … `:END:` and `:LOGBOOK:` … `:END:` |

### Global fold cycle (`<S-Tab>`)

| State | Effect |
|---|---|
| **OVERVIEW** | All folds closed — only top-level headlines visible |
| **CONTENTS** | All headlines visible, content and blocks folded |
| **SHOW ALL** | Everything open |

### Quick toggle (`{leader}f`)

`{leader}f` is a smart two-state toggle:

- If **any** headline fold is currently closed → open everything (`zR`, SHOW ALL).
- If **all** folds are open → close everything (`zM`, OVERVIEW).

Use it to quickly collapse the whole file to headlines-only and expand back with the same key.

### Per-item (`<Tab>`)

`<Tab>` on a **headline**, `#+BEGIN_*` line, or drawer opening line (`:PROPERTIES:`, `:LOGBOOK:`) toggles that fold open/closed.
`<Tab>` on any other line sends a normal `>>` indent.

---

## Keeping Your Config Safe

Plugin updates (via `:PlugUpdate`) only touch files inside the plugin directory.
To keep your customisation separate and update-safe:

1. Copy the template:

   ```sh
   # Linux / macOS
   cp ~/.vim/plugged/vim-org/config/user.vim ~/.vim/after/plugin/org_user.vim

   # Windows
   copy %USERPROFILE%\vimfiles\plugged\vim-org\config\user.vim ^
        %USERPROFILE%\vimfiles\after\plugin\org_user.vim
   ```

2. Edit `~/.vim/after/plugin/org_user.vim` freely. Vim loads `after/plugin/`
   **after** all plugins, so your file always wins.

3. After editing, apply changes with `:OrgReload`.

---

## File Layout

```
vim-org/
├── autoload/org/
│   ├── agenda.vim      – agenda views (week / day / month / todo / deadlines)
│   ├── archive.vim     – archive subtree to *.org_archive
│   ├── cal.vim         – interactive calendar popup widget
│   ├── capture.vim     – quick-capture template
│   ├── checkbox.vim    – checkbox toggle, parent summary update
│   ├── clock.vim       – clock in/out, LOGBOOK management
│   ├── clockreport.vim – clock report generator (#+BEGIN: clocktable)
│   ├── config.vim      – OrgReload implementation
│   ├── core.vim        – shared utilities (keyword parser, JDN, logbook)
│   ├── date.vim        – SCHEDULED / DEADLINE insertion with calendar + time
│   ├── dispatch.vim    – <C-c><C-c> context action (:OrgCtrlC)
│   ├── fold.vim        – foldexpr, foldtext, Tab / S-Tab handlers, block border
│   ├── headline.vim    – promote/demote (subtree + visual range)
│   ├── highlight.vim   – all highlight group definitions (survives colorscheme reloads)
│   ├── id.vim          – :ID: property generation
│   ├── link.vim        – link opening ([[url]], [[file:]], [[id:]])
│   ├── priority.vim    – priority cycling [#A] / [#B] / [#C]
│   ├── tags.vim        – tag editing
│   └── todo.vim        – TODO cycle logic, CLOSED timestamp, repeaters
├── config/
│   └── user.vim        – user config template (not auto-loaded)
├── ftdetect/
│   └── org.vim         – sets filetype=org for *.org files
├── ftplugin/
│   └── org.vim         – buffer-local settings, mappings, leader resolution
├── plugin/
│   ├── org.vim         – plugin guard + command definitions
│   └── org_defaults.vim – default values for all g:org_* variables
└── syntax/
    └── org.vim         – full syntax definitions and highlight groups
```
