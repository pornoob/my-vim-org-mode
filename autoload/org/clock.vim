" ── Duration formatting ───────────────────────────────────────────────────────

function! s:format_duration(seconds) abort
  let total_mins = a:seconds / 60
  let h = total_mins / 60
  let m = total_mins % 60
  return printf('%d:%02d', h, m)
endfunction

" ── Julian Day Number (proleptic Gregorian calendar) ─────────────────────────
" Used to convert calendar dates to a day count for epoch arithmetic.

function! s:jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
endfunction

" ── Stored timestamp → Unix epoch ────────────────────────────────────────────
" Accepts the 5 matchlist captures from an inactive timestamp [YYYY-MM-DD dow HH:MM].
" Returns local epoch (same basis as localtime()) for duration arithmetic.
" TZ offset is derived from the current moment as a proxy; any DST drift is
" bounded to < 1 hour and negligible for time-tracking purposes.

function! s:parse_ts(y, mo, d, h, mi) abort
  " "As if UTC" epoch for the local wall-clock components stored in the string
  let utc_eq = (s:jdn(a:y + 0, a:mo + 0, a:d + 0) - s:jdn(1970, 1, 1)) * 86400
        \ + (a:h + 0) * 3600 + (a:mi + 0) * 60

  " Derive local TZ offset: tz_offset = localtime() - ("local wall time as UTC").
  " Result is negative east of UTC (e.g. -7200 for UTC+2).
  let now = localtime()
  let utc_eq_now = (s:jdn(strftime('%Y', now) + 0,
        \               strftime('%m', now) + 0,
        \               strftime('%d', now) + 0)
        \           - s:jdn(1970, 1, 1)) * 86400
        \ + strftime('%H', now) * 3600
        \ + strftime('%M', now) * 60
        \ + strftime('%S', now)
  let tz_offset = now - utc_eq_now

  " Adding tz_offset converts "local as UTC" → true UTC epoch
  return utc_eq + tz_offset
endfunction

" ── Scan buffer for open clock entry ─────────────────────────────────────────
" An open entry has exactly one [timestamp] and nothing after it on the line.
" Returns the line number, or 0 if none found.

function! s:find_open_clock() abort
  let pat = '^\s*CLOCK:\s*\[\d\{4}-\d\{2}-\d\{2}\s\+\a\{3}\s\+\d\{2}:\d\{2}\]\s*$'
  for lnum in range(1, line('$'))
    if getline(lnum) =~# pat
      return lnum
    endif
  endfor
  return 0
endfunction

" ── Insert an open CLOCK entry into the LOGBOOK ──────────────────────────────

function! s:clock_in_at(headline_lnum) abort
  let ts           = org#core#format_ts(localtime(), 0)
  let logbook_lnum = org#core#ensure_logbook(a:headline_lnum)
  " Insert right after :LOGBOOK: so newest entry appears first (Emacs convention)
  call append(logbook_lnum, '  CLOCK: ' . ts)
endfunction

" ── Close an open CLOCK entry ─────────────────────────────────────────────────

function! s:clock_out_at(clock_lnum) abort
  let l = getline(a:clock_lnum)

  " Re-use the exact start-timestamp string from the stored line to avoid
  " any re-formatting artifacts (e.g. daylight-saving rounding).
  let ts_in = matchstr(l, '\[.\{-}\]')
  if empty(ts_in)
    echohl WarningMsg
    echo 'org: no timestamp found on clock line ' . a:clock_lnum
    echohl None
    return
  endif

  " Parse components for duration arithmetic
  let m = matchlist(ts_in,
        \ '\[\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)\s\+\a\{3}\s\+\(\d\{2}\):\(\d\{2}\)\]')
  if empty(m)
    echohl WarningMsg
    echo 'org: malformed clock timestamp: ' . ts_in
    echohl None
    return
  endif

  let now         = localtime()
  let start_epoch = s:parse_ts(m[1], m[2], m[3], m[4], m[5])
  let elapsed     = now - start_epoch
  " Guard against negative elapsed (clock-in in the future, or DST edge case)
  if elapsed < 0 | let elapsed = 0 | endif

  let ts_out  = org#core#format_ts(now, 0)
  let dur_str = s:format_duration(elapsed)
  let indent  = matchstr(l, '^\s*')

  " Org format: CLOCK: [start]--[end] =>  H:MM  (two spaces before hours)
  call setline(a:clock_lnum,
        \ indent . 'CLOCK: ' . ts_in . '--' . ts_out . ' =>  ' . dur_str)
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

" Clock in on the headline at or above the cursor.
" If another clock is already running anywhere in the buffer, it is closed first.
function! org#clock#in() abort
  let hl = org#core#current_headline()
  if empty(hl)
    echo 'org: not under a headline'
    return
  endif

  let open_lnum = s:find_open_clock()
  if open_lnum > 0
    " Auto-close the running clock before starting a new one
    call s:clock_out_at(open_lnum)
  endif

  call s:clock_in_at(hl.lnum)
  echo 'org: clocked in on "' . hl.text . '"'
endfunction

" Close the open clock entry (anywhere in the buffer).
function! org#clock#out() abort
  let open_lnum = s:find_open_clock()
  if open_lnum == 0
    echo 'org: no active clock'
    return
  endif
  call s:clock_out_at(open_lnum)
  echo 'org: clocked out'
endfunction

" Toggle: clock out if a clock is running, clock in if idle.
function! org#clock#toggle() abort
  if s:find_open_clock() > 0
    call org#clock#out()
  else
    call org#clock#in()
  endif
endfunction
