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
    if index(a:kw.done, a:new_kw) >= 0
      call s:log_closed(lnum)
    endif
  endif
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

function! s:log_closed(headline_lnum) abort
  if s:handle_repeat(a:headline_lnum)
    return
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

function! s:handle_repeat(headline_lnum) abort
  let lnum = a:headline_lnum + 1
  while lnum <= line('$') && lnum <= a:headline_lnum + 5
    let l = getline(lnum)
    let inner = matchstr(l, '\%(SCHEDULED\|DEADLINE\):\s*<\zs[^>]*\ze>')
    if inner ==# ''
      if l !~# '^\s*\%(SCHEDULED\|DEADLINE\):'
        break
      endif
      let lnum += 1
      continue
    endif

    let rm = matchlist(inner, '\(++\|\.+\|+\)\(\d\+\)\([dwmy]\)$')
    if empty(rm)
      let lnum += 1
      continue
    endif

    let prefix = rm[1]
    let num    = str2nr(rm[2])
    let unit   = rm[3]
    let old_date = matchstr(inner, '^\d\{4}-\d\{2}-\d\{2}')

    let now = localtime()
    let base_epoch = s:repeat_base_epoch(prefix, old_date, now)
    if base_epoch < 0
      let lnum += 1
      continue
    endif

    let new_epoch = s:add_period(base_epoch, num, unit)
    if prefix ==# '.+'
      while new_epoch <= now
        let new_epoch = s:add_period(new_epoch, num, unit)
      endwhile
    endif

    let new_stamp = s:format_repeat_stamp(new_epoch)
    let kw = matchstr(l, 'SCHEDULED\|DEADLINE')
    call setline(lnum, substitute(l, '<[^>]*>', new_stamp, ''))
    call s:reset_to_first_active(a:headline_lnum)
    echo 'org: ' . kw . ' repeated — ' . new_stamp
    return 1
  endwhile
  return 0
endfunction

function! s:repeat_base_epoch(prefix, old_date_str, now_epoch) abort
  if a:prefix ==# '+'
    let m = matchlist(a:old_date_str, '^\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)$')
    if empty(m) | return -1 | endif
    return s:date_epoch(m[1]+0, m[2]+0, m[3]+0)
  endif
  return a:now_epoch
endfunction

function! s:date_epoch(y, m, d) abort
  let now = localtime()
  let jdn  = s:jdn(a:y, a:m, a:d)
  let diff = jdn - s:jdn(strftime('%Y', now)+0, strftime('%m', now)+0, strftime('%d', now)+0)
  return s:midnight_today() + diff * 86400
endfunction

function! s:jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
endfunction

function! s:midnight_today() abort
  let now = localtime()
  return now - strftime('%H', now) * 3600 - strftime('%M', now) * 60 - strftime('%S', now)
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

function! s:format_repeat_stamp(epoch) abort
  return strftime('<%Y-%m-%d %a>', a:epoch)
endfunction

function! s:reset_to_first_active(headline_lnum) abort
  let kw = org#core#keywords()
  if empty(kw.all)
    return
  endif
  let first = kw.active[0]
  let line = getline(a:headline_lnum)
  let m = matchlist(line, '^\(\*\+\s\+\)\(.*\)$')
  if empty(m)
    return
  endif
  let rest = m[2]
  for state in kw.all
    if rest =~# '^\C' . state . '\>'
      return
    endif
  endfor
  call setline(a:headline_lnum, m[1] . first . ' ' . rest)
endfunction
