" Scan the current buffer for #+SEQ_TODO: or #+TODO: file-local directives.
" Returns {active, done, all, shortcuts, has_shortcuts} if found, {} otherwise.
" Keywords like TODO(t) have their shortcut extracted; stripped name is used.
function! org#core#file_keywords() abort
  let active    = []
  let done      = []
  let shortcuts = {}
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
        " Parse optional shortcut: TODO(t) → kw='TODO', key='t'
        let km = matchlist(tok, '^\([^(]\+\)(\(.\))$')
        if !empty(km)
          let kw  = km[1]
          let shortcuts[km[2]] = kw
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
          \ }
  endfor

  return {}
endfunction

" Returns {active, done, all, shortcuts, has_shortcuts}.
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

  call append(last_meta, ['  :LOGBOOK:', '  :END:'])
  return last_meta + 1
endfunction
