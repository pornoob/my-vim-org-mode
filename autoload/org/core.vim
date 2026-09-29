" Scan the current buffer for #+SEQ_TODO: or #+TODO: file-local directives.
" Returns {active, done, all, shortcuts, has_shortcuts, log} if found, {}
" otherwise. Keywords like TODO(t) have their shortcut extracted; stripped name
" is used. log maps a state to [on_enter, on_leave], each '!' (timestamp),
" '@' (timestamp + note) or '': DONE(d@/!) → {'DONE': ['@', '!']}.
function! org#core#file_keywords() abort
  let active    = []
  let done      = []
  let shortcuts = {}
  let log       = {}
  let in_done   = 0

  for lnum in range(1, min([line('$'), 200]))
    let m = matchlist(getline(lnum), '^\c\s*#+\%(SEQ_TODO\|TODO\):\s*\(.*\)$')
    if empty(m)
      continue
    endif
    for tok in split(m[1], '\s\+')
      if tok ==# '|'
        let in_done = 1
      else
        " Parse optional shortcut + logging spec: TODO(t), DONE(d@/!),
        " WAIT(@/!) → kw, and key when the spec starts with one
        let km = matchlist(tok, '^\([^(]\+\)(\([^)]*\))$')
        if !empty(km)
          let kw  = km[1]
          let key = matchstr(km[2], '^[^@!/]')
          if !empty(key)
            let shortcuts[key] = kw
          endif
          let spec = split(km[2][len(key):], '/', 1)
          if !empty(join(spec, ''))
            let log[kw] = [matchstr(spec[0], '[@!]'),
                  \ matchstr(get(spec, 1, ''), '[@!]')]
          endif
        else
          let kw = tok
        endif
        call add(in_done ? done : active, kw)
      endif
    endfor
    return {
          \ 'active':        active,
          \ 'done':          done,
          \ 'all':           active + done,
          \ 'shortcuts':     shortcuts,
          \ 'has_shortcuts': !empty(shortcuts),
          \ 'log':           log,
          \ }
  endfor

  return {}
endfunction

" Returns {active, done, all, shortcuts, has_shortcuts, log}.
" Priority: #+SEQ_TODO in file > g:org_todo_keywords > built-in defaults.
function! org#core#keywords() abort
  let file_kw = org#core#file_keywords()
  if !empty(file_kw)
    return file_kw
  endif

  let raw = get(g:, 'org_todo_keywords', ['TODO', '|', 'DONE'])

  if type(raw[0]) == type([])
    let active = raw[0]
    let done   = len(raw) > 1 ? raw[1] : []
  else
    let active  = []
    let done    = []
    let in_done = 0
    for word in raw
      if word ==# '|'
        let in_done = 1
      elseif in_done
        call add(done, word)
      else
        call add(active, word)
      endif
    endfor
  endif

  return {
        \ 'active':        active,
        \ 'done':          done,
        \ 'all':           active + done,
        \ 'shortcuts':     {},
        \ 'has_shortcuts': 0,
        \ 'log':           {},
        \ }
endfunction

" Returns the current headline dict or {} if cursor is not on/under one
function! org#core#current_headline() abort
  let lnum = line('.')
  while lnum > 0
    let line = getline(lnum)
    let m = matchlist(line, '^\(\*\+\)\s\+\(.*\)$')
    if !empty(m)
      return {'lnum': lnum, 'level': len(m[1]), 'text': m[2], 'line': line}
    endif
    let lnum -= 1
  endwhile
  return {}
endfunction

function! org#core#jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
endfunction

function! org#core#jdn_to_ymd(jdn) abort
  let a  = a:jdn + 32044
  let b  = (4 * a + 3) / 146097
  let c  = a - (146097 * b) / 4
  let d  = (4 * c + 3) / 1461
  let e  = c - (1461 * d) / 4
  let mo = (5 * e + 2) / 153
  return [100 * b + d - 4800 + mo / 10,
        \ mo + 3 - 12 * (mo / 10),
        \ e - (153 * mo + 2) / 5 + 1]
endfunction

function! org#core#days_in_month(y, m) abort
  if a:m == 2
    return (a:y % 4 == 0 && (a:y % 100 != 0 || a:y % 400 == 0)) ? 29 : 28
  endif
  return (a:m == 4 || a:m == 6 || a:m == 9 || a:m == 11) ? 30 : 31
endfunction

" Resolve g:org_agenda_files into a list of .org files.
" Entries are expanded first: isdirectory() and filereadable() do NOT expand
" '~' or $VARs, so a '~/org' entry would otherwise match neither branch and be
" skipped silently. Falls back to the current buffer when nothing is configured.
function! org#core#agenda_files() abort
  let entries = get(g:, 'org_agenda_files', [])
  if empty(entries)
    let cur = expand('%:p')
    return (filereadable(cur) && &filetype ==# 'org') ? [cur] : []
  endif

  let files = []
  for raw_entry in entries
    let entry = expand(raw_entry)
    " Try native path then forward-slash variant (Windows compat)
    let fwd = substitute(entry, '\\', '/', 'g')
    if isdirectory(entry) || isdirectory(fwd)
      " Strip trailing separator, then glob recursively
      let base = substitute(fwd, '[/\\]$', '', '')
      " Collect top-level and nested .org files (deduplicated)
      let raw = glob(base . '/*.org', 0, 1) + glob(base . '/**/*.org', 0, 1)
      let seen = {}
      for rf in raw
        if !has_key(seen, rf) | let seen[rf] = 1 | call add(files, rf) | endif
      endfor
      unlet seen
    elseif filereadable(entry) || filereadable(fwd)
      call add(files, entry)
    endif
  endfor
  return files
endfunction

" Locale day-name abbreviation for a calendar date, matching what
" format_ts()'s strftime('%a') would emit (es_CL: lun mar mié jue vie sáb dom).
" Anchored at local noon and stepped in whole days, so neither the timezone
" offset nor a DST shift can push the result onto the wrong calendar day.
function! org#core#dow(y, m, d) abort
  let now  = localtime()
  let noon = now - (strftime('%H', now) * 3600
        \           + strftime('%M', now) * 60
        \           + strftime('%S', now)) + 43200
  let delta = org#core#jdn(a:y, a:m, a:d)
        \   - org#core#jdn(strftime('%Y', now) + 0,
        \                 strftime('%m', now) + 0,
        \                 strftime('%d', now) + 0)
  return strftime('%a', noon + delta * 86400)
endfunction

" Rewrite every timestamp's day name in {line} so it agrees with its date.
" Only a genuine day-name token is touched: one that is not a time (12:00),
" a repeater (+1d, ++1w, .+2m) or a delay (-1d), and a timestamp written
" without a day name at all is left exactly as it is.
function! org#core#fix_dow(line) abort
  return substitute(a:line,
        \ '[[<]\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)\s\+\zs[^]> \t0-9+.-][^]> \t]*',
        \ '\=org#core#dow(submatch(1) + 0, submatch(2) + 0, submatch(3) + 0)',
        \ 'g')
endfunction

function! org#core#format_ts(time, active) abort
  let fmt = a:active ? '<%Y-%m-%d %a %H:%M>' : '[%Y-%m-%d %a %H:%M]'
  return strftime(fmt, a:time)
endfunction

" Find or create :LOGBOOK: drawer for the headline at headline_lnum.
" Walks forward past planning lines and :PROPERTIES: to find an existing
" :LOGBOOK:. If none exists, inserts one and returns its line number.
function! org#core#ensure_logbook(headline_lnum) abort
  let lnum      = a:headline_lnum + 1
  let last_meta = a:headline_lnum

  while lnum <= line('$')
    let l = getline(lnum)

    if l =~# '^\s*$'
      let lnum += 1

    elseif l =~# '^\s*\%(SCHEDULED:\|DEADLINE:\|CLOSED:\)'
      let last_meta = lnum
      let lnum += 1

    elseif l =~# '^\s*:LOGBOOK:'
      return lnum

    elseif l =~# '^\s*:PROPERTIES:'
      let last_meta = lnum
      let lnum += 1
      while lnum <= line('$')
        let last_meta = lnum
        if getline(lnum) =~# '^\s*:END:'
          let lnum += 1
          break
        endif
        let lnum += 1
      endwhile

    elseif l =~# '^\*'
      break

    else
      break
    endif
  endwhile

  " Indent like the entry's own metadata; two spaces when it has none
  let indent = last_meta > a:headline_lnum ? matchstr(getline(last_meta), '^\s*') : '  '
  call append(last_meta, [indent . ':LOGBOOK:', indent . ':END:'])
  return last_meta + 1
endfunction

" Scan the header block of the entry at {headline_lnum}: planning lines, blank
" lines and complete drawers, in whatever order the file happens to use. Some
" files put :LOGBOOK: before :PROPERTIES:, so the scan must step over a whole
" drawer instead of giving up at the first one it meets.
" Returns {'props': [start, end], 'insert_after': lnum, 'indent': str};
" props is [0, 0] when the entry has no :PROPERTIES: drawer.
function! org#core#scan_header(headline_lnum) abort
  let lnum         = a:headline_lnum + 1
  let last         = line('$')
  let insert_after = a:headline_lnum
  let props        = [0, 0]
  let indent       = ''

  while lnum <= last
    let l = getline(lnum)

    if l =~# '^\s*$'
      let lnum += 1

    elseif l =~# '^\s*\%(SCHEDULED:\|DEADLINE:\|CLOSED:\)'
      " A new :PROPERTIES: drawer belongs just after the planning lines
      let insert_after = lnum
      if empty(indent) | let indent = matchstr(l, '^\s*') | endif
      let lnum += 1

    elseif l =~# '^\s*:\a[[:alnum:]_-]*:\s*$' && l !~? '^\s*:END:\s*$'
      let is_props = l =~? '^\s*:PROPERTIES:\s*$'
      let dstart   = lnum
      let lnum    += 1
      while lnum <= last && getline(lnum) !~? '^\s*:END:\s*$'
            \ && getline(lnum) !~# '^\*'
        let lnum += 1
      endwhile
      if lnum > last || getline(lnum) !~? '^\s*:END:\s*$'
        break   " unterminated drawer: do not walk off into the rest of the file
      endif
      if is_props && props[0] == 0
        let props  = [dstart, lnum]
        let indent = matchstr(l, '^\s*')
      elseif empty(indent)
        let indent = matchstr(l, '^\s*')
      endif
      let lnum += 1

    else
      break
    endif
  endwhile

  return {'props': props, 'insert_after': insert_after, 'indent': indent}
endfunction

" Set property {key} of the entry at {headline_lnum} to {value}: rewrite the
" line when the key is already there, else add it to the entry's :PROPERTIES:
" drawer, creating the drawer after the planning lines when there is none.
function! org#core#set_property(headline_lnum, key, value) abort
  let hdr  = org#core#scan_header(a:headline_lnum)
  " Emacs org-property-format: key column 10 wide, then one space
  let line = hdr.indent . printf('%-10s %s', ':' . a:key . ':', a:value)

  if hdr.props[0] > 0
    for lnum in range(hdr.props[0] + 1, hdr.props[1] - 1)
      if getline(lnum) =~? '^\s*:' . a:key . ':'
        call setline(lnum, matchstr(getline(lnum), '^\s*') . printf('%-10s %s', ':' . a:key . ':', a:value))
        return
      endif
    endfor
    call append(hdr.props[1] - 1, line)
    return
  endif

  call append(hdr.insert_after, [hdr.indent . ':PROPERTIES:', hdr.indent . ':END:'])
  call append(hdr.insert_after + 1, line)
endfunction

" Add a log item at the top of the entry's :LOGBOOK: (newest first, as Emacs
" does), indented like the drawer. {lines}[0] is the item text; any further
" lines are a note, attached with Emacs' ' \\' line break.
function! org#core#log_item(headline_lnum, lines) abort
  let lb     = org#core#ensure_logbook(a:headline_lnum)
  let indent = matchstr(getline(lb), '^\s*')
  let item   = [indent . '- ' . a:lines[0] . (len(a:lines) > 1 ? ' \\' : '')]
  call append(lb, item + map(a:lines[1:], 'indent . "  " . v:val'))
endfunction

" One tag character, as Emacs' org-tag-re allows: any letter or digit (not
" just ASCII: :VEHÍCULOS: is a tag) plus _ @ # %. Vim's \w and [:alnum:] are
" ASCII-only, so the class is "not space, not ASCII punctuation" plus those.
function! org#core#tag_char() abort
  return '\%([^[:space:][:punct:]]\|[_@#%]\)'
endfunction

" Pattern for the tag block ':a:b:' at the end of a headline. Callers put
" '\s\+' (or '\s\zs') in front: Emacs needs whitespace before the block.
function! org#core#tags_pattern() abort
  return ':\%(' . org#core#tag_char() . '\+:\)\+\s*$'
endfunction

" Return {entry} (a subtree's lines) with every headline shifted so the
" shallowest one sits at {level}; lines that are not headlines are kept.
function! org#core#set_level(entry, level) abort
  let levels = map(filter(copy(a:entry), {_, l -> l =~# '^\*\+ '}),
        \ {_, l -> len(matchstr(l, '^\*\+'))})
  if empty(levels)
    return copy(a:entry)
  endif
  let shift = a:level - min(levels)
  return map(copy(a:entry), {_, l -> l !~# '^\*\+ ' ? l
        \ : repeat('*', len(matchstr(l, '^\*\+')) + shift) . matchstr(l, '^\*\+\zs.*')})
endfunction

" Return {lines} (a file's lines) with {entry} filed as the last child of the
" headline {heading}, a whole line such as '* Inbox': at the end of that
" subtree, re-levelled to sit one level below it. A missing {heading} is
" appended at the end first. This is what Emacs does for capture's
" file+headline target and for an archive location with a heading.
function! org#core#file_entry(lines, heading, entry) abort
  let lines = copy(a:lines)
  let level = len(matchstr(a:heading, '^\*\+'))
  let hl_idx = index(lines, a:heading)
  if hl_idx < 0
    call add(lines, a:heading)
    let hl_idx = len(lines) - 1
  endif

  " End of the heading's subtree: the next headline of its level or higher
  let insert_at = hl_idx + 1
  while insert_at < len(lines)
        \ && !(lines[insert_at] =~# '^\*\+ ' && len(matchstr(lines[insert_at], '^\*\+')) <= level)
    let insert_at += 1
  endwhile

  return lines[: insert_at - 1] + org#core#set_level(a:entry, level + 1) + lines[insert_at :]
endfunction

" Headline {text} (what follows the stars) without its TODO keyword, priority
" cookie and tags: the title Emacs uses in outline paths and [[*Title]] links.
function! org#core#headline_title(text) abort
  let t   = a:text
  let kws = org#core#keywords().all
  if !empty(kws)
    let t = substitute(t, '^\C\%(' . join(map(copy(kws), 'escape(v:val, "\\")'), '\|') . '\)\s\+', '', '')
  endif
  let t = substitute(t, '^\[#.\]\s*', '', '')
  let t = substitute(t, '\s\+' . org#core#tags_pattern(), '', '')
  return trim(t)
endfunction
