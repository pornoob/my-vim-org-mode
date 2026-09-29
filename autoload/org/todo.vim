" Forward cycle or shortcut-select prompt (when #+SEQ_TODO defines shortcuts).
function! org#todo#cycle() abort
  let kw = org#core#keywords()
  if kw.has_shortcuts
    call s:select_state(kw)
  else
    call s:shift(1, kw)
  endif
endfunction

function! org#todo#cycle_back() abort
  call s:shift(-1, org#core#keywords())
endfunction

" ── internals ────────────────────────────────────────────────────────────────

" Parse the headline at the cursor into [stars, current_kw, rest].
" Returns [] if not on a headline.
function! s:headline_parts(kw) abort
  let line = getline('.')
  if line !~# '^\*'
    return []
  endif
  let all = a:kw.all
  if !empty(all)
    let kw_pat = '^\(\*\+\s\+\)\(\%('
          \ . join(map(copy(all), 'escape(v:val, "\\")'), '\|')
          \ . '\):*\s\+\)\(.*\)$'
    let m = matchlist(line, kw_pat)
    if !empty(m)
      " Strip trailing colon + whitespace from the matched keyword token
      return [m[1], substitute(m[2], ':\?\s\+$', '', ''), m[3]]
    endif
  endif
  " No keyword on this headline
  let m2 = matchlist(line, '^\(\*\+\s\+\)\(.*\)$')
  return empty(m2) ? [] : [m2[1], '', m2[2]]
endfunction

" Apply new_kw (empty = clear state) to the headline at the cursor.
function! s:apply_state(new_kw, kw) abort
  let lnum  = line('.')
  let parts = s:headline_parts(a:kw)
  if empty(parts)
    echo 'org: not on a headline'
    return
  endif
  let [stars, cur, rest] = parts
  if empty(a:new_kw)
    call setline(lnum, stars . rest)
    echo 'org: (no state)'
  else
    call setline(lnum, stars . a:new_kw . ' ' . rest)
    echo 'org: ' . a:new_kw
    let repeated = 0
    if index(a:kw.done, a:new_kw) >= 0
      let repeated = s:log_closed(lnum)
    endif
    if a:new_kw !=# cur
      call s:log_state(lnum, a:new_kw, cur, a:kw, repeated)
    endif
  endif
endfunction

" Log a state change into :LOGBOOK: the way Emacs does with
" org-log-into-drawer: the new state's on-enter marker wins, else the old
" state's on-leave one ('!' = timestamp, '@' = timestamp + note). An entry
" that just repeated is logged per g:org_log_repeat, which also stamps
" :LAST_REPEAT:.
function! s:log_state(lnum, new, old, kw, repeated) abort
  let how = get(get(a:kw.log, a:new, []), 0, '')
  if empty(how)
    let how = get(get(a:kw.log, a:old, []), 1, '')
  endif
  let ts = org#core#format_ts(localtime(), 0)

  let rep = get(g:, 'org_log_repeat', 'time')
  if a:repeated && !empty(rep)
    call org#core#set_property(a:lnum, 'LAST_REPEAT', ts)
    if how !=# '@'
      let how = rep ==# 'note' ? '@' : '!'
    endif
  endif
  if empty(how)
    return
  endif

  let item = [printf('State %-12s from %-12s %s',
        \ '"' . a:new . '"', '"' . a:old . '"', ts)]
  if how ==# '@'
    let note = trim(input('Note (' . a:new . '): '))
    if !empty(note)
      call add(item, note)
    endif
  endif
  call org#core#log_item(a:lnum, item)
endfunction

" Sequential cycle: dir=+1 forward, dir=-1 backward.
function! s:shift(dir, kw) abort
  let parts = s:headline_parts(a:kw)
  if empty(parts)
    echo 'org: not on a headline'
    return
  endif
  let [stars, current, rest] = parts
  let all = a:kw.all

  if !empty(current)
    let next_idx = index(all, current) + a:dir
  else
    let next_idx = a:dir > 0 ? 0 : len(all) - 1
  endif

  let new_kw = (next_idx < 0 || next_idx >= len(all)) ? '' : all[next_idx]
  call s:apply_state(new_kw, a:kw)
endfunction

" Shortcut-key prompt: shown when #+SEQ_TODO defines (key) bindings.
" Displays a one-line menu and reads a single keypress.
function! s:select_state(kw) abort
  if getline('.') !~# '^\*'
    echo 'org: not on a headline'
    return
  endif

  " Build reverse map state → shortcut key for display
  let rev = {}
  for [key, state] in items(a:kw.shortcuts)
    let rev[state] = key
  endfor

  let parts = []
  for state in a:kw.all
    let key = get(rev, state, '')
    call add(parts, empty(key) ? state : key . ':' . state)
  endfor

  echon 'State (' . join(parts, '  ') . '  SPC:clear): '
  let ch   = getchar()
  let char = type(ch) == type(0) ? nr2char(ch) : ch
  echo ''

  if char ==# ' '
    call s:apply_state('', a:kw)
  elseif has_key(a:kw.shortcuts, char)
    call s:apply_state(a:kw.shortcuts[char], a:kw)
  else
    echo 'org: no state bound to ' . string(char)
  endif
endfunction

" Stamp CLOSED on an entry just marked done, or repeat it when its planning
" stamps carry a repeater. Returns 1 when the entry repeated.
function! s:log_closed(headline_lnum) abort
  if s:handle_repeat(a:headline_lnum)
    return 1
  endif

  let ts   = org#core#format_ts(localtime(), 0)
  let lnum = a:headline_lnum + 1

  while lnum <= line('$') && lnum <= a:headline_lnum + 5
    let l = getline(lnum)
    if l =~# '^\s*CLOSED:'
      call setline(lnum, substitute(l, '\[.\{-}\]', ts, ''))
      return
    elseif l =~# '^\s*\(SCHEDULED:\|DEADLINE:\|:PROPERTIES:\|:LOGBOOK:\|$\)'
      let lnum += 1
    else
      break
    endif
  endwhile

  call append(a:headline_lnum, '  CLOSED: ' . ts)
endfunction

" Shift every repeating SCHEDULED/DEADLINE stamp in the planning lines under
" {headline_lnum}, the way Emacs org-auto-repeat-maybe does. Only the date and
" day name change: time, repeater and warning delay are kept. Returns 1 when
" at least one stamp was repeated (the entry then stays open, no CLOSED line).
function! s:handle_repeat(headline_lnum) abort
  let s:repeated = []
  let lnum = a:headline_lnum + 1
  while lnum <= line('$') && lnum <= a:headline_lnum + 5
    let l = getline(lnum)
    if l !~# '^\s*\%(SCHEDULED\|DEADLINE\|CLOSED\):'
      break
    endif
    let new = substitute(l, '\(SCHEDULED\|DEADLINE\):\s*\zs<[^>]*>',
          \ '\=s:repeat_stamp(submatch(0), submatch(1))', 'g')
    if new !=# l
      call setline(lnum, new)
    endif
    let lnum += 1
  endwhile

  if empty(s:repeated)
    return 0
  endif
  call s:reset_to_first_active(a:headline_lnum)
  echo 'org: repeated — ' . join(s:repeated, '  ')
  return 1
endfunction

" Return {stamp} ('<2026-07-01 Wed 09:00 +1m -2d>') moved to its next
" occurrence, or unchanged when it carries no repeater.
"   +N   old date + N units (may still be in the past)
"   ++N  old date + N units, repeated until it lands after today
"   .+N  today + N units
function! s:repeat_stamp(stamp, kw) abort
  let rm = matchlist(a:stamp, '\s\(++\|\.+\|+\)\(\d\+\)\([dwmy]\)\>')
  let dm = matchlist(a:stamp, '^<\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)')
  if empty(rm) || empty(dm)
    return a:stamp
  endif
  let [prefix, num, unit] = [rm[1], str2nr(rm[2]), rm[3]]
  if num <= 0
    return a:stamp
  endif

  let today = s:noon_today()
  let base  = prefix ==# '.+' ? today : s:date_epoch(dm[1]+0, dm[2]+0, dm[3]+0)
  let next  = s:add_period(base, num, unit)
  if prefix ==# '++'
    while next <= today
      let next = s:add_period(next, num, unit)
    endwhile
  endif

  let [y, m, d] = s:epoch_to_ymd(next)
  let date = printf('%04d-%02d-%02d %s', y, m, d, org#core#dow(y, m, d))
  let stamp = substitute(a:stamp,
        \ '^<\d\{4}-\d\{2}-\d\{2}\%(\s\+[^> \t0-9+.-][^> \t]*\)\=',
        \ '<' . escape(date, '\&'), '')
  call add(s:repeated, a:kw . ' ' . stamp)
  return stamp
endfunction

" Epoch at noon of {y}-{m}-{d}. Noon, not midnight: a DST jump shifts the
" wall clock by an hour, which from midnight lands on the previous day.
function! s:date_epoch(y, m, d) abort
  let now = localtime()
  let jdn  = s:jdn(a:y, a:m, a:d)
  let diff = jdn - s:jdn(strftime('%Y', now)+0, strftime('%m', now)+0, strftime('%d', now)+0)
  return s:noon_today() + diff * 86400
endfunction

function! s:jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
endfunction

function! s:noon_today() abort
  let now = localtime()
  return now - strftime('%H', now) * 3600 - strftime('%M', now) * 60 - strftime('%S', now)
        \ + 43200
endfunction

function! s:add_period(epoch, num, unit) abort
  if a:unit ==# 'd'
    return a:epoch + a:num * 86400
  elseif a:unit ==# 'w'
    return a:epoch + a:num * 7 * 86400
  elseif a:unit ==# 'm'
    return s:add_months(a:epoch, a:num)
  elseif a:unit ==# 'y'
    return s:add_months(a:epoch, a:num * 12)
  endif
  return a:epoch
endfunction

function! s:add_months(epoch, months) abort
  let ymd = s:epoch_to_ymd(a:epoch)
  let total_m = ymd[1] + a:months
  let y = ymd[0] + (total_m - 1) / 12
  let m = ((total_m - 1) % 12) + 1
  let d = min([ymd[2], s:days_in_month(y, m)])
  return s:date_epoch(y, m, d)
endfunction

function! s:epoch_to_ymd(epoch) abort
  let arr = strftime('%Y %m %d', a:epoch)
  return map(split(arr), 'v:val + 0')
endfunction

function! s:days_in_month(y, m) abort
  if a:m == 2
    return (a:y % 4 == 0 && (a:y % 100 != 0 || a:y % 400 == 0)) ? 29 : 28
  endif
  return (a:m == 4 || a:m == 6 || a:m == 9 || a:m == 11) ? 30 : 31
endfunction

" Put a repeated headline back to the first active keyword, replacing the done
" state that was just applied (Emacs does the same after org-auto-repeat).
function! s:reset_to_first_active(headline_lnum) abort
  let kw = org#core#keywords()
  if empty(kw.active)
    return
  endif
  let m = matchlist(getline(a:headline_lnum), '^\(\*\+\s\+\)\(.*\)$')
  if empty(m)
    return
  endif
  let rest = m[2]
  for state in kw.all
    if rest =~# '^\C' . state . '\>'
      let rest = substitute(rest[len(state):], '^\s*', '', '')
      break
    endif
  endfor
  call setline(a:headline_lnum, m[1] . kw.active[0] . ' ' . rest)
endfunction
