" ── Date / epoch helpers ─────────────────────────────────────────────────────

function! s:jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
endfunction

" Epoch of local midnight today
function! s:midnight_today() abort
  let now = localtime()
  return now - strftime('%H', now) * 3600
             \ - strftime('%M', now) * 60
             \ - strftime('%S', now)
endfunction

" Epoch of midnight on an arbitrary local date.
" Computed as (JDN difference from today) * 86400 + midnight_today
" so TZ/DST never enters the calculation.
function! s:date_epoch(y, m, d) abort
  let now  = localtime()
  let diff = s:jdn(a:y, a:m, a:d)
           \ - s:jdn(strftime('%Y', now)+0, strftime('%m', now)+0, strftime('%d', now)+0)
  return s:midnight_today() + diff * 86400
endfunction

" Format an epoch as an Org active date stamp.
" Optional second argument is a time string 'HH:MM'; if given the stamp
" becomes <YYYY-MM-DD Day HH:MM> (specific-time form).
function! s:fmt(epoch, ...) abort
  let t = get(a:, 1, '')
  let d = strftime('%Y-%m-%d %a', a:epoch)
  return empty(t) ? '<' . d . '>' : '<' . d . ' ' . t . '>'
endfunction

" ── Input parser ──────────────────────────────────────────────────────────────
"
" Accepted formats:
"   today  /  .             → today
"   tomorrow                → tomorrow
"   +N  /  +Nd              → N days from today
"   +Nw                     → N weeks
"   +Nm                     → N months (approx 30 days each)
"   YYYY-MM-DD              → exact date
"
" Returns epoch on success, -1 on unrecognized input.

function! s:parse_input(raw) abort
  let s = substitute(a:raw, '^\s\+\|\s\+$', '', 'g')
  if s ==# '' | return -1 | endif

  if s ==# 'today' || s ==# '.'
    return s:midnight_today()
  endif

  if s ==# 'tomorrow'
    return s:midnight_today() + 86400
  endif

  " +N / +Nd / +Nw / +Nm
  let m = matchlist(s, '^+\(\d\+\)\([dwm]\?\)$')
  if !empty(m)
    let n    = str2nr(m[1])
    let unit = empty(m[2]) ? 'd' : m[2]
    if unit ==# 'w' | let n = n * 7  | endif
    if unit ==# 'm' | let n = n * 30 | endif
    return s:midnight_today() + n * 86400
  endif

  " YYYY-MM-DD
  let m = matchlist(s, '^\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)$')
  if !empty(m)
    return s:date_epoch(m[1]+0, m[2]+0, m[3]+0)
  endif

  return -1
endfunction

" ── Reschedule log ────────────────────────────────────────────────────────────

function! s:log_reschedule(headline_lnum, old_ts) abort
  let now_ts = org#core#format_ts(localtime(), 0)
  let entry  = '  - Rescheduled from "' . a:old_ts . '" on ' . now_ts
  call append(org#core#ensure_logbook(a:headline_lnum), entry)
endfunction

" ── Planning line management ──────────────────────────────────────────────────

" Insert or update a SCHEDULED / DEADLINE line under the nearest headline.
" If the keyword is already present it is updated in-place; otherwise a new
" line is inserted after any existing planning lines.
" When an existing date is replaced, a reschedule note is added to LOGBOOK.
function! s:set_planning(keyword, ts_str) abort
  let hl = org#core#current_headline()
  if empty(hl)
    echo 'org: not under a headline'
    return
  endif

  let lnum         = hl.lnum + 1
  let insert_after = hl.lnum
  let found        = 0
  let old_ts       = ''

  while lnum <= line('$') && lnum <= hl.lnum + 10
    let l = getline(lnum)
    if l !~# '^\s*\%(SCHEDULED\|DEADLINE\|CLOSED\):'
      break
    endif
    if l =~# '\<' . a:keyword . '\>:'
      " Capture the existing timestamp before overwriting it
      let old_ts = matchstr(l, '<[^>]*>')
      if l =~# '\<' . a:keyword . '\>:\s*<[^>]*>'
        call setline(lnum, substitute(l,
              \ '\<' . a:keyword . '\>:\s*<[^>]*>',
              \ a:keyword . ': ' . a:ts_str, ''))
      else
        call setline(lnum, substitute(l,
              \ '\<' . a:keyword . '\>:',
              \ a:keyword . ': ' . a:ts_str, ''))
      endif
      let found = 1
      break
    endif
    let insert_after = lnum
    let lnum += 1
  endwhile

  if !found
    call append(insert_after, '  ' . a:keyword . ': ' . a:ts_str)
  elseif old_ts !=# '' && old_ts !=# a:ts_str
    " Date was changed (not first insert) — log it
    call s:log_reschedule(hl.lnum, old_ts)
  endif
endfunction

" ── Calendar callback ─────────────────────────────────────────────────────────

" Called when the calendar popup confirms a date (YYYY-MM-DD) or cancels ('').
function! s:on_date_picked(keyword, date_str) abort
  if a:date_str ==# ''
    return
  endif

  let m = matchlist(a:date_str, '^\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)$')
  if empty(m)
    return
  endif

  " Optional time prompt (popup is already closed here)
  redraw
  let time_str = ''
  try
    let time_raw = input('Time (HH:MM or Enter to skip): ')
  catch /^Vim:Interrupt$/
    let time_raw = ''
  endtry
  echo ''

  if time_raw !=# ''
    if time_raw =~# '^\d\{1,2}:\d\{2}$'
      let parts    = split(time_raw, ':')
      let time_str = printf('%02d:%02d', parts[0]+0, parts[1]+0)
    else
      echohl WarningMsg
      echo 'org: invalid time "' . time_raw . '" — scheduled without time'
      echohl None
    endif
  endif

  let epoch = s:date_epoch(m[1]+0, m[2]+0, m[3]+0)
  call s:set_planning(a:keyword, s:fmt(epoch, time_str))
endfunction

" ── Text-prompt fallback ──────────────────────────────────────────────────────

" Used when has('popupwin') is false.
" Accepts an optional HH:MM suffix: 'today 14:30' or '+7d 09:00'.
function! s:text_prompt(keyword) abort
  redraw
  let hint = a:keyword . ' (YYYY-MM-DD [HH:MM]  today  +7d  +2w  +1m): '
  try
    let raw = input(hint)
  catch /^Vim:Interrupt$/
    echo '' | return
  endtry
  echo ''

  if raw ==# ''
    echo 'org: cancelled'
    return
  endif

  " Strip optional trailing time (HH:MM or H:MM)
  let time_str = ''
  let tm = matchlist(raw, '\s\+\(\d\{1,2}:\d\{2}\)$')
  if !empty(tm)
    let parts    = split(tm[1], ':')
    let time_str = printf('%02d:%02d', parts[0]+0, parts[1]+0)
    let raw      = substitute(raw, '\s\+\d\{1,2}:\d\{2}$', '', '')
  endif

  let epoch = s:parse_input(raw)
  if epoch < 0
    echohl WarningMsg
    echo 'org: unrecognized date "' . raw . '"'
    echohl None
    return
  endif

  call s:set_planning(a:keyword, s:fmt(epoch, time_str))
endfunction

" ── Entry point ───────────────────────────────────────────────────────────────

function! s:prompt(keyword) abort
  let hl = org#core#current_headline()
  if empty(hl)
    echo 'org: not under a headline'
    return
  endif

  if has('popupwin')
    call org#cal#pick({date_str -> s:on_date_picked(a:keyword, date_str)})
  else
    call s:text_prompt(a:keyword)
  endif
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

function! org#date#schedule() abort
  call s:prompt('SCHEDULED')
endfunction

function! org#date#deadline() abort
  call s:prompt('DEADLINE')
endfunction
