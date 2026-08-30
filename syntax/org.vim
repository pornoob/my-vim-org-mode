if exists('b:current_syntax') | finish | endif

" ── Determine keyword lists ───────────────────────────────────────────────────
" Priority: #+SEQ_TODO / #+TODO in file  >  g:org_todo_keywords  >  built-in

let s:active = []
let s:done   = []
let s:found  = 0

for s:lnum in range(1, min([line('$'), 200]))
  let s:dm = matchlist(getline(s:lnum),
        \ '^\c\s*#+\%(SEQ_TODO\|TODO\):\s*\(.*\)$')
  if !empty(s:dm)
    let s:found = 1
    let s:ind   = 0
    for s:tok in split(s:dm[1], '\s\+')
      if s:tok ==# '|'
        let s:ind = 1
      else
        let s:kw = substitute(s:tok, '([^)]*)$', '', '')
        if !empty(s:kw)
          call add(s:ind ? s:done : s:active, s:kw)
        endif
      endif
    endfor
    break
  endif
endfor
unlet! s:lnum s:dm s:ind s:tok s:kw

if !s:found
  let s:raw = get(g:, 'org_todo_keywords', ['TODO', '|', 'DONE'])
  if type(s:raw[0]) == type([])
    let s:active = s:raw[0]
    let s:done   = len(s:raw) > 1 ? s:raw[1] : []
  else
    let s:in_done = 0
    for s:w in s:raw
      if s:w ==# '|'        | let s:in_done = 1
      elseif s:in_done      | call add(s:done,   s:w)
      else                  | call add(s:active, s:w)
      endif
    endfor
    unlet s:in_done s:w
  endif
  unlet s:raw
endif
unlet s:found

" ── Default colour ramp (used when g:org_todo_keyword_faces has no entry) ────
"
"  Active keywords get warm bold tones (up to 5), cycling if there are more.
"  Done keywords get muted tones (up to 2), cycling thereafter.
"
"  Each entry is either:
"    • a raw :highlight spec   'ctermfg=… guifg=…'
"    • a highlight group name  'Error'
"
let s:ramp_active = [
  \ 'ctermfg=167 cterm=bold guifg=#fb4934 gui=bold',
  \ 'ctermfg=208 cterm=bold guifg=#fe8019 gui=bold',
  \ 'ctermfg=214 cterm=bold guifg=#fabd2f gui=bold',
  \ 'ctermfg=175 cterm=bold guifg=#d3869b gui=bold',
  \ 'ctermfg=109 cterm=bold guifg=#83a598 gui=bold',
  \ ]
let s:ramp_done = [
  \ 'ctermfg=142 cterm=NONE guifg=#b8bb26 gui=NONE',
  \ 'ctermfg=245 cterm=NONE guifg=#928374 gui=strikethrough',
  \ ]

let s:custom = get(g:, 'org_todo_keyword_faces', {})

" ── Create one syntax group + highlight per keyword ──────────────────────────
"
"  Group name: orgKw_{KEYWORD}  (e.g. orgKw_TODO, orgKw_DONE)
"  Users set g:org_todo_keyword_faces to override individual keywords:
"
"    let g:org_todo_keyword_faces = {
"      \ 'TODO':    'ctermfg=196 cterm=bold guifg=#ff0000 gui=bold',
"      \ 'WAITING': 'Question',
"      \ }
"
let s:kw_groups = []

for s:i in range(len(s:active))
  let s:kw  = s:active[s:i]
  let s:grp = 'orgKw_' . s:kw
  call add(s:kw_groups, s:grp)
  execute 'syntax keyword ' . s:grp . ' contained ' . s:kw
  let s:face = get(s:custom, s:kw,
        \ s:ramp_active[s:i % len(s:ramp_active)])
  if s:face =~# '\s'
    execute 'highlight ' . s:grp . ' ' . s:face
  else
    execute 'highlight link ' . s:grp . ' ' . s:face
  endif
endfor

for s:i in range(len(s:done))
  let s:kw  = s:done[s:i]
  let s:grp = 'orgKw_' . s:kw
  call add(s:kw_groups, s:grp)
  execute 'syntax keyword ' . s:grp . ' contained ' . s:kw
  let s:face = get(s:custom, s:kw,
        \ s:ramp_done[s:i % len(s:ramp_done)])
  if s:face =~# '\s'
    execute 'highlight ' . s:grp . ' ' . s:face
  else
    execute 'highlight link ' . s:grp . ' ' . s:face
  endif
endfor

" ── Headlines (8 levels) with dynamic contains clause ────────────────────────

let s:hl_contains = join(s:kw_groups
      \ + ['orgPriorityA','orgPriorityB','orgPriorityC','orgPriority',
      \    'orgTag','orgTimestampActive','orgTimestampInactive',
      \    'orgCheckboxSummary','orgCheckboxDone','orgCheckboxIndet','orgCheckboxTodo'], ',')

let s:hl_starts = [
      \ '/^\*\s/',        '/^\*\*\s/',       '/^\*\*\*\s/',     '/^\*\*\*\*\s/',
      \ '/^\*\{5}\s/',    '/^\*\{6}\s/',     '/^\*\{7}\s/',     '/^\*\{8,}\s/',
      \ ]

for s:lvl in range(1, 8)
  execute 'syntax region orgHeadline' . s:lvl
        \ . ' matchgroup=orgStars' . s:lvl
        \ . ' start=' . s:hl_starts[s:lvl - 1]
        \ . ' end=/$/'
        \ . ' contains=' . s:hl_contains
        \ . ' oneline keepend'
endfor

unlet s:active s:done s:ramp_active s:ramp_done s:custom
unlet s:kw_groups s:hl_contains s:hl_starts s:grp s:kw s:face s:i s:lvl

" ── Priority [#A] [#B] [#C] — each level gets its own colour ────────────────
syntax match orgPriorityA /\[#A\]/ contained
syntax match orgPriorityB /\[#B\]/ contained
syntax match orgPriorityC /\[#C\]/ contained
syntax match orgPriority  /\[#[D-Z]\]/ contained

" ── Tags :foo:bar: at end of headline ─────────────────────────────────────────
syntax match orgTag /\(:\w\+\)\+:$/ contained

" ── Timestamps ────────────────────────────────────────────────────────────────
syntax match orgTimestampActive   /<\d\{4}-\d\{2}-\d\{2}\%(\s\+[^>0-9 \t]\+\)\?\%(\s\+\d\{2}:\d\{2}\)\?>/
syntax match orgTimestampInactive /\[\d\{4}-\d\{2}-\d\{2}\%(\s\+[^]0-9 \t]\+\)\?\%(\s\+\d\{2}:\d\{2}\)\?\]/

" ── Planning lines ────────────────────────────────────────────────────────────
syntax match orgPlanning /^\s*\%(SCHEDULED\|DEADLINE\|CLOSED\):/
      \ nextgroup=orgTimestampActive,orgTimestampInactive skipwhite

" ── Properties drawer ─────────────────────────────────────────────────────────
" keepend: don't let orgPropertyKey matching :END: prevent the region from closing
syntax region orgProperties start=/^\s*:PROPERTIES:/ end=/^\s*:END:/
      \ contains=orgPropertyKey keepend fold
" Exclude drawer delimiters (:END: :PROPERTIES: :LOGBOOK:) from property keys
" by using a negative lookahead for those exact keyword+colon sequences.
syntax match orgPropertyKey /^\s*:\%(PROPERTIES:\|END:\|LOGBOOK:\)\@!\w[^:]*:/ contained

" ── LOGBOOK drawer + CLOCK lines ──────────────────────────────────────────────
syntax region orgLogbook start=/^\s*:LOGBOOK:/ end=/^\s*:END:/
      \ contains=orgClockLine keepend fold
syntax match orgClockLine     /^\s*CLOCK:.*$/    contained
      \ contains=orgTimestampInactive,orgClockDuration
syntax match orgClockDuration /=>\s*\d\+:\d\{2}/ contained

" ── Source / example / quote blocks ───────────────────────────────────────────
" Design notes:
"   \c = case-insensitive  (#+begin_src and #+BEGIN_SRC both work)
"   \> = end-of-word boundary  (\b in Vim regex is a literal backspace char!)
"
"   We do NOT use matchgroup so the #+BEGIN_* / #+END_* delimiter lines sit
"   inside the region and inherit its background tint.
"
"   orgBlockBound is defined LAST in this section so it has the highest syntax
"   priority — it wins over embedded language rules (e.g. Python's # comment)
"   on the delimiter lines.
"
"   Region priority: the LAST defined region wins when two match at the same
"   position.  Generic orgSrcBlock is defined first; language-specific regions
"   come after and therefore win.

syntax region orgExampleBlock
      \ start=/\c^#+BEGIN_EXAMPLE\>/ end=/\c^#+END_EXAMPLE\>/
      \ contains=orgBlockBound keepend fold

syntax region orgQuoteBlock
      \ start=/\c^#+BEGIN_QUOTE\>/ end=/\c^#+END_QUOTE\>/
      \ contains=orgBlockBound keepend fold

" Generic #+BEGIN_SRC fallback — defined first so language-specific wins later
syntax region orgSrcBlock
      \ start=/\c^#+BEGIN_SRC\>/ end=/\c^#+END_SRC\>/
      \ contains=orgBlockBound keepend fold

" Scan the whole buffer for #+BEGIN_SRC language names and embed their syntax.
let s:org_lang_seen = {}
for s:ln in range(1, line('$'))
  let s:ll = tolower(matchstr(getline(s:ln), '\c^#+BEGIN_SRC\s\+\zs\S\+'))
  if !empty(s:ll) | let s:org_lang_seen[s:ll] = 1 | endif
endfor
for [s:lang, s:_dummy] in items(s:org_lang_seen)
  " Map common org-mode aliases to Vim filetype/syntax names
  let s:vft = get({
        \ 'elisp': 'lisp', 'emacs-lisp': 'lisp',
        \ 'bash': 'sh', 'zsh': 'sh', 'ksh': 'sh', 'fish': 'sh',
        \ 'js': 'javascript', 'jsx': 'javascript',
        \ 'ts': 'typescript', 'tsx': 'typescript',
        \ 'py': 'python',
        \ 'rb': 'ruby',
        \ 'c++': 'cpp',
        \ 'yml': 'yaml',
        \ 'vimscript': 'vim', 'vimrc': 'vim',
        \ }, s:lang, s:lang)
  let s:id  = substitute(s:lang, '[^a-zA-Z0-9]', '_', 'g')
  let s:cl  = 'OrgSrc_' . s:id
  let s:pat = escape(s:lang, '/\')
  try
    execute 'syntax include @' . s:cl . ' syntax/' . s:vft . '.vim'
    " Language-specific region — defined after orgSrcBlock so it wins
    execute 'syntax region orgSrcBlock_' . s:id
          \ . ' start=/\c^#+BEGIN_SRC\s\+' . s:pat . '\>/'
          \ . ' end=/\c^#+END_SRC\>/'
          \ . ' contains=@' . s:cl . ',orgBlockBound keepend fold'
  catch
    " No Vim syntax file for this language — orgSrcBlock generic handles it
  endtry
endfor
unlet! s:ln s:ll s:lang s:_dummy s:vft s:id s:cl s:pat s:org_lang_seen

" orgBlockBound MUST be last: highest priority beats embedded language syntax
" (e.g. Python's # comment) on the #+BEGIN_* / #+END_* delimiter lines.
" Also used by matchadd() in fold.vim for fold-text colouring.
syntax match orgBlockBound /\c^#+\%(BEGIN\|END\)_\w\+/ contained

" ── Metadata / comments ───────────────────────────────────────────────────────
" ^#+ is a literal hash-plus; \w matches any case so #+title: and #+TITLE: both color.
syntax match orgMetaKey /^#+\w\+:/
syntax match orgComment /^#\s.*$\|^#$/

" ── Links [[url]] or [[url][desc]] ───────────────────────────────────────────
syntax match orgLink /\[\[[^\]]*\]\(\[[^\]]*\]\)\?\]/

" ── Inline markup ─────────────────────────────────────────────────────────────
" Opening delimiter must be preceded by whitespace or start of line so that
" slashes in URLs (://) and file paths (actividad/servicio) never match.
syntax match orgBold     /\%(^\|\s\)\zs\*\S[^*\n]*\S\*\ze\%(\s\|$\)\|\%(^\|\s\)\zs\*\S\*\ze\%(\s\|$\)/
syntax match orgItalic   /\%(^\|\s\)\zs\/\S[^/\n]*\S\/\ze\%(\s\|$\)\|\%(^\|\s\)\zs\/\S\/\ze\%(\s\|$\)/
syntax match orgCode     /\~\S.\{-}\S\~\|\~\S\~/
syntax match orgVerbatim /=\S.\{-}\S=\|=\S=/
syntax match orgStrike   /+\S.\{-}\S+\|+\S+/

" ── Sync: always parse from top of file to avoid stale state ─────────────────
syntax sync fromstart

" ── Lists & misc ──────────────────────────────────────────────────────────────
syntax match orgListBullet /^\s*[-+]\s/
syntax match orgListNum    /^\s*\d\+[.)]\s/
syntax match orgCheckboxDone  /\[X\]/
syntax match orgCheckboxIndet /\[-\]/
syntax match orgCheckboxTodo  /\[ \?\]/
syntax match orgCheckboxSummary /\[\(\d*\/\d*\|\d*%\)\]/
syntax match orgHRule      /^-----\+$/

" ── Apply highlight groups via shared function ────────────────────────────────
call org#highlight#apply()

let b:current_syntax = 'org'
