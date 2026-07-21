" ── Calendar popup widget ────────────────────────────────────────────────────
" org#cal#pick(callback) opens a month-view popup; navigate with h/j/k/l/n/p.
" callback is called with 'YYYY-MM-DD' on confirm or '' on cancel.
" Requires Vim 8 popup windows (has('popupwin')).

" ── Date arithmetic ───────────────────────────────────────────────────────────

function! s:jdn(y, m, d) abort
  let a  = (14 - a:m) / 12
  let y  = a:y + 4800 - a
  let mo = a:m + 12 * a - 3
  return a:d + (153 * mo + 2) / 5 + 365 * y + y/4 - y/100 + y/400 - 32045
endfunction

function! s:jdn_to_ymd(jdn) abort
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

function! s:days_in_month(y, m) abort
  if a:m == 2
    return (a:y % 4 == 0 && (a:y % 100 != 0 || a:y % 400 == 0)) ? 29 : 28
  endif
  return (a:m == 4 || a:m == 6 || a:m == 9 || a:m == 11) ? 30 : 31
endfunction

" Returns 0 (Mon) … 6 (Sun) for day 1 of the given month.
" Anchored to JDN 2460311 = 2024-01-01 (Monday) which gives JDN%7 == 0 for Monday.
function! s:first_weekday(y, m) abort
  return s:jdn(a:y, a:m, 1) % 7
endfunction

" ── Script-level state ────────────────────────────────────────────────────────

let s:cal = {'year': 0, 'month': 0, 'day': 0, 'cb': 0, 'winid': -1}

let s:month_names = ['January','February','March','April','May','June',
      \ 'July','August','September','October','November','December']

" ── Rendering ─────────────────────────────────────────────────────────────────

function! s:render() abort
  let y  = s:cal.year
  let m  = s:cal.month
  let d  = s:cal.day
  let dm = s:days_in_month(y, m)
  let fw = s:first_weekday(y, m)     " 0=Mon … 6=Sun for day 1

  " Title: centered in 28 chars (content width = minwidth)
  let title = s:month_names[m - 1] . ' ' . y
  let pad   = (28 - len(title)) / 2
  let lines = [repeat(' ', pad) . title]

  " Weekday header (26 chars; popup pads to 28)
  call add(lines, 'Mo  Tu  We  Th  Fr  Sa  Su')

  " Day rows — each cell is 4 chars: printf('%2d','  ')+two-spaces
  let row = repeat('    ', fw)       " leading blanks for the weekday offset
  let col = fw                       " current column (0=Mon … 6=Sun)

  for day in range(1, dm)
    let row .= printf('%2d', day) . '  '
    let col  += 1
    if col == 7
      call add(lines, row[:-3])      " trim trailing two spaces
      let row = ''
      let col = 0
    endif
  endfor
  if col > 0
    call add(lines, row[:-3])
  endif

  call popup_settext(s:cal.winid, lines)

  " Highlight the selected day with Visual group.
  " Compute line/column of 'd' in the popup content (1-based).
  let day_offset = s:jdn(y, m, d) - s:jdn(y, m, 1)   " 0-based index in grid
  let abs_col    = fw + day_offset
  let pop_line   = (abs_col / 7) + 3                  " +1 title +1 header +1-base
  let pop_col    = (abs_col % 7) * 4 + 1              " each cell 4 wide, 1-based

  let pat = '\%' . pop_line . 'l\%' . pop_col . 'c.\{2\}'
  call win_execute(s:cal.winid, 'call clearmatches()')
  call win_execute(s:cal.winid, 'call matchadd("Visual", ' . string(pat) . ', 10)')
endfunction

" ── Keyboard filter ───────────────────────────────────────────────────────────

function! s:filter(winid, key) abort
  let y = s:cal.year
  let m = s:cal.month
  let d = s:cal.day

  if a:key ==# 'h' || a:key ==# "\<Left>"
    let jdn = s:jdn(y, m, d) - 1
    let ymd = s:jdn_to_ymd(jdn)
    let [s:cal.year, s:cal.month, s:cal.day] = ymd

  elseif a:key ==# 'l' || a:key ==# "\<Right>"
    let jdn = s:jdn(y, m, d) + 1
    let ymd = s:jdn_to_ymd(jdn)
    let [s:cal.year, s:cal.month, s:cal.day] = ymd

  elseif a:key ==# 'k' || a:key ==# "\<Up>"
    let jdn = s:jdn(y, m, d) - 7
    let ymd = s:jdn_to_ymd(jdn)
    let [s:cal.year, s:cal.month, s:cal.day] = ymd

  elseif a:key ==# 'j' || a:key ==# "\<Down>"
    let jdn = s:jdn(y, m, d) + 7
    let ymd = s:jdn_to_ymd(jdn)
    let [s:cal.year, s:cal.month, s:cal.day] = ymd

  elseif a:key ==# 'n'
    let m += 1
    if m > 12 | let m = 1 | let y += 1 | endif
    let [s:cal.year, s:cal.month, s:cal.day] = [y, m, min([d, s:days_in_month(y, m)])]

  elseif a:key ==# 'p' || a:key ==# 'N'
    let m -= 1
    if m < 1 | let m = 12 | let y -= 1 | endif
    let [s:cal.year, s:cal.month, s:cal.day] = [y, m, min([d, s:days_in_month(y, m)])]

  elseif a:key ==# "\<CR>" || a:key ==# "\<NL>"
    let result = printf('%04d-%02d-%02d', s:cal.year, s:cal.month, s:cal.day)
    call popup_close(a:winid, result)
    return 1

  elseif a:key ==# "\<Esc>" || a:key ==# 'q'
    call popup_close(a:winid, '')
    return 1

  else
    return 0
  endif

  call s:render()
  return 1
endfunction

" ── Popup close callback ──────────────────────────────────────────────────────

function! s:on_close(winid, result) abort
  let s:cal.winid = -1
  call call(s:cal.cb, [type(a:result) == type('') ? a:result : ''])
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

" Open an interactive calendar popup. callback('YYYY-MM-DD') on confirm,
" callback('') on cancel. Falls back to callback('') when no popup support.
function! org#cal#pick(callback) abort
  if !has('popupwin')
    call call(a:callback, [''])
    return
  endif

  let now = localtime()
  let s:cal.year  = strftime('%Y', now) + 0
  let s:cal.month = strftime('%m', now) + 0
  let s:cal.day   = strftime('%d', now) + 0
  let s:cal.cb    = a:callback

  let s:cal.winid = popup_create([], {
        \ 'border':      [],
        \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ 'padding':     [0, 1, 0, 1],
        \ 'mapping':     0,
        \ 'filter':      function('s:filter'),
        \ 'callback':    function('s:on_close'),
        \ 'minwidth':    28,
        \ 'maxwidth':    28,
        \ 'fixed':       1,
        \ })

  call s:render()
endfunction
