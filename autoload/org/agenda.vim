" ── Org Agenda ───────────────────────────────────────────────────────────────
" Four views: week / month / todo / deadlines
" Public API: org#agenda#open(), #refresh(), #next(), #prev(), #today(),
"             #set_view(v), #jump(), #preview()

" ── Script-level state ────────────────────────────────────────────────────────

if !exists('s:ag')
  let s:ag = {
        \ 'view':     'week',
        \ 'base_jdn': 0,
        \ 'focus_jdn': 0,
        \ 'link_map': {},
        \ 'bufnr':    -1,
        \ }
endif

let s:day_names  = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
let s:day_short  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun']
let s:month_names = ['January','February','March','April','May','June',
      \ 'July','August','September','October','November','December']

" ── Date helpers ──────────────────────────────────────────────────────────────

function! s:today_jdn() abort
  let now = localtime()
  return org#core#jdn(strftime('%Y', now)+0, strftime('%m', now)+0, strftime('%d', now)+0)
endfunction

" Unix epoch for midnight of a date given as JDN
function! s:jdn_to_epoch(jdn) abort
  let now     = localtime()
  let now_jdn = org#core#jdn(strftime('%Y',now)+0, strftime('%m',now)+0, strftime('%d',now)+0)
  let midnight = now - strftime('%H',now)*3600 - strftime('%M',now)*60 - strftime('%S',now)
  return midnight + (a:jdn - now_jdn) * 86400
endfunction

function! s:epoch_to_jdn(epoch) abort
  return org#core#jdn(1970, 1, 1) + a:epoch / 86400
endfunction

" Parse an active-timestamp inner string → midnight epoch (-1 on failure)
" Accepts '2026-07-14 Mon' or '2026-07-14 Mon 09:00'
function! s:parse_ts(inner) abort
  let m = matchlist(a:inner, '^\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)')
  if empty(m) | return -1 | endif
  return s:jdn_to_epoch(org#core#jdn(m[1]+0, m[2]+0, m[3]+0))
endfunction

" Monday of the ISO week containing jdn (weekday 0=Mon … 6=Sun)
function! s:week_monday(jdn) abort
  return a:jdn - (a:jdn % 7)
endfunction

" ISO week number
function! s:iso_week(jdn) abort
  let thu = a:jdn + (3 - a:jdn % 7)
  let year_start = org#core#jdn(org#core#jdn_to_ymd(thu)[0], 1, 1)
  return (thu - year_start) / 7 + 1
endfunction

" Format JDN as 'Mon Jul 14' style
function! s:fmt_day(jdn) abort
  let ymd = org#core#jdn_to_ymd(a:jdn)
  let wd  = a:jdn % 7
  return s:day_short[wd] . ' ' . s:month_names[ymd[1]-1][:2] . ' ' . printf('%2d', ymd[2])
endfunction

" Return 1 if a timestamp (base_epoch + repeat) falls on jdn.
" rep_n=0 means no repeat — only the base date matches.
" Handles +Nd (daily), +Nw (weekly), +Nm (monthly), +Ny (yearly).
" Matches all three org repeat styles (+, .+, ++).
function! s:occurs_on(jdn, base_epoch, rep_n, rep_unit) abort
  if a:base_epoch < 0 | return 0 | endif
  let base_jdn = s:epoch_to_jdn(a:base_epoch)
  if a:jdn < base_jdn | return 0 | endif
  if a:rep_n <= 0
    return a:jdn == base_jdn ? 1 : 0
  endif
  let diff = a:jdn - base_jdn
  if a:rep_unit ==# 'd'
    return diff % a:rep_n == 0 ? 1 : 0
  elseif a:rep_unit ==# 'w'
    return diff % (a:rep_n * 7) == 0 ? 1 : 0
  elseif a:rep_unit ==# 'm'
    let b = org#core#jdn_to_ymd(base_jdn)
    let c = org#core#jdn_to_ymd(a:jdn)
    let md = (c[0] - b[0]) * 12 + (c[1] - b[1])
    return (md >= 0 && md % a:rep_n == 0 && c[2] == b[2]) ? 1 : 0
  elseif a:rep_unit ==# 'y'
    let b = org#core#jdn_to_ymd(base_jdn)
    let c = org#core#jdn_to_ymd(a:jdn)
    let yd = c[0] - b[0]
    return (yd >= 0 && yd % a:rep_n == 0 && c[1] == b[1] && c[2] == b[2]) ? 1 : 0
  endif
  return 0
endfunction

" ── File scanning ─────────────────────────────────────────────────────────────


" Read keywords from g:org_todo_keywords directly — never from buffer content,
" so agenda scanning is not affected by whichever buffer happens to be current.
function! s:kw_dict() abort
  let raw = get(g:, 'org_todo_keywords', ['TODO', '|', 'DONE'])
  if type(raw[0]) == type([])
    let active = raw[0]
    let done   = len(raw) > 1 ? raw[1] : []
  else
    let active = [] | let done = [] | let in_done = 0
    for w in raw
      if w ==# '|' | let in_done = 1
      elseif in_done | call add(done, w)
      else           | call add(active, w)
      endif
    endfor
  endif
  return {'active': active, 'done': done, 'all': active + done}
endfunction

" Parse a scanned file's own #+SEQ_TODO: / #+TODO: directive from its lines.
" Agenda scanning must not consult the *current buffer*, but each file's own
" keywords are authoritative for that file (PAYED, REPEAT, MISSED ...).
" Returns {} when the file declares none, so the global list is used instead.
function! s:file_kw(lines) abort
  let active = []
  let done   = []
  for l in a:lines[0 : min([len(a:lines), 200]) - 1]
    let m = matchlist(l, '^\c\s*#+\%(SEQ_TODO\|TODO\):\s*\(.*\)$')
    if empty(m) | continue | endif
    let in_done = 0
    for tok in split(m[1], '\s\+')
      if tok ==# '|'
        let in_done = 1
      else
        " Strip the shortcut/logging suffix: DONE(d@/!) -> DONE
        let k = substitute(tok, '([^)]*)$', '', '')
        if !empty(k) | call add(in_done ? done : active, k) | endif
      endif
    endfor
    return {'active': active, 'done': done, 'all': active + done}
  endfor
  return {}
endfunction

function! s:scan_files() abort
  let kw    = s:kw_dict()
  let items = []
  for f in org#core#agenda_files()
    call extend(items, s:scan_file(f, kw))
  endfor
  return items
endfunction

function! s:scan_file(path, kw) abort
  let items  = []
  let lines  = readfile(a:path)
  let nlines = len(lines)
  " File-local #+SEQ_TODO wins for this file; else the global keyword list
  let fkw    = s:file_kw(lines)
  let kwset  = empty(fkw) ? a:kw : fkw
  let all_kw = kwset.all
  let lnum   = 0

  while lnum < nlines
    let line = lines[lnum]
    let hm   = matchlist(line, '^\(\*\+\)\s\+\(.*\)$')

    if !empty(hm)
      let text = hm[2]

      " Extract TODO state
      let state = ''
      for kw in all_kw
        if text =~# '^\C' . kw . '\%(\s\|$\)'
          let state = kw
          let text  = substitute(text, '^\C' . kw . '\s*', '', '')
          break
        endif
      endfor

      " Extract and strip priority [#X]
      let prio = matchstr(text, '^\[#\zs.\ze\]')
      let text = substitute(text, '^\[#.\]\s*', '', '')
      " Strip trailing tags :foo:bar:
      let text = substitute(text, '\s\+:[[:alnum:]_@#%:]\+:\s*$', '', '')
      let text = substitute(text, '^\s\+\|\s\+$', '', 'g')

      let item = {
            \ 'file':                   a:path,
            \ 'lnum':                   lnum + 1,
            \ 'level':                  len(hm[1]),
            \ 'state':                  state,
            \ 'is_done':                 (!empty(state) && index(kwset.done, state) >= 0),
            \ 'priority':               prio,
            \ 'text':                   text,
            \ 'scheduled_epoch':        -1,
            \ 'deadline_epoch':         -1,
            \ 'scheduled_time':         '',
            \ 'deadline_time':          '',
            \ 'scheduled_repeat_n':     0,
            \ 'scheduled_repeat_unit':  '',
            \ 'deadline_repeat_n':      0,
            \ 'deadline_repeat_unit':   '',
            \ }

      " Look ahead for SCHEDULED/DEADLINE planning lines (up to 5 lines)
      let look = lnum + 1
      while look < nlines && look <= lnum + 5
        let pl = lines[look]
        if pl !~# '^\s*\%(SCHEDULED\|DEADLINE\|CLOSED\):'
          break
        endif
        let sm = matchstr(pl, 'SCHEDULED:\s*<\zs[^>]*\ze>')
        if sm !=# ''
          let item.scheduled_epoch = s:parse_ts(sm)
          let item.scheduled_time  = matchstr(sm, '\d\{2}:\d\{2}$')
          let rpm = matchlist(sm, '[.+]\?+\(\d\+\)\([dwmy]\)')
          if !empty(rpm)
            let item.scheduled_repeat_n    = rpm[1] + 0
            let item.scheduled_repeat_unit = rpm[2]
          endif
        endif
        let dm = matchstr(pl, 'DEADLINE:\s*<\zs[^>]*\ze>')
        if dm !=# ''
          let item.deadline_epoch = s:parse_ts(dm)
          let item.deadline_time  = matchstr(dm, '\d\{2}:\d\{2}$')
          let rpm = matchlist(dm, '[.+]\?+\(\d\+\)\([dwmy]\)')
          if !empty(rpm)
            let item.deadline_repeat_n    = rpm[1] + 0
            let item.deadline_repeat_unit = rpm[2]
          endif
        endif
        let look += 1
      endwhile

      call add(items, item)
    endif

    let lnum += 1
  endwhile

  return items
endfunction

" ── Buffer / window management ────────────────────────────────────────────────

function! org#agenda#open() abort
  " Re-use an existing agenda buffer if it's still alive
  if s:ag.bufnr != -1 && bufexists(s:ag.bufnr)
    let wins = win_findbuf(s:ag.bufnr)
    if !empty(wins)
      call win_gotoid(wins[0])
    else
      execute 'topleft ' . g:org_agenda_window_height . ' split'
      execute 'buffer ' . s:ag.bufnr
    endif
    call org#agenda#refresh()
    return
  endif

  let height = get(g:, 'org_agenda_window_height', 20)
  execute 'topleft ' . height . ' split'
  enew

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nocursorcolumn
  setlocal nowrap
  silent! file [Org Agenda]

  let s:ag.bufnr     = bufnr('%')
  let s:ag.base_jdn  = s:week_monday(s:today_jdn())
  let s:ag.focus_jdn = s:today_jdn()

  call s:setup_maps()
  call org#agenda#refresh()
endfunction

function! s:setup_maps() abort
  nnoremap <buffer> <silent> n      :call org#agenda#next()<CR>
  nnoremap <buffer> <silent> p      :call org#agenda#prev()<CR>
  nnoremap <buffer> <silent> .      :call org#agenda#today()<CR>
  nnoremap <buffer> <silent> <CR>   :call org#agenda#jump()<CR>
  nnoremap <buffer> <silent> o      :call org#agenda#preview()<CR>
  nnoremap <buffer> <silent> r      :call org#agenda#refresh()<CR>
  nnoremap <buffer> <silent> g      :call org#agenda#refresh()<CR>
  nnoremap <buffer> <silent> q      :close<CR>
  nnoremap <buffer> <silent> W      :call org#agenda#set_view('week')<CR>
  nnoremap <buffer> <silent> A      :call org#agenda#set_view('day')<CR>
  nnoremap <buffer> <silent> M      :call org#agenda#set_view('month')<CR>
  nnoremap <buffer> <silent> T      :call org#agenda#set_view('todo')<CR>
  nnoremap <buffer> <silent> D      :call org#agenda#set_view('deadlines')<CR>

  " TODO cycling on the source headline — same leader as ftplugin/org.vim
  let l = exists('g:org_leader') ? g:org_leader
        \ : exists('g:maplocalleader') ? g:maplocalleader : '\'
  execute 'nnoremap <buffer> <silent> ' . l . 't :call org#agenda#todo(1)<CR>'
  execute 'nnoremap <buffer> <silent> ' . l . 'T :call org#agenda#todo(-1)<CR>'

  " In month view j/k move the focused day; elsewhere scroll normally
  nnoremap <buffer> <silent> j :call org#agenda#cursor_down()<CR>
  nnoremap <buffer> <silent> k :call org#agenda#cursor_up()<CR>
  nnoremap <buffer> <silent> h :call org#agenda#cursor_left()<CR>
  nnoremap <buffer> <silent> l :call org#agenda#cursor_right()<CR>

  " Syntax
  syntax clear
  syntax match orgAgendaSep     /^[─━]\+/
  syntax match orgAgendaHeader  /^ Org Agenda .*/
  syntax match orgAgendaHint    /^ W week.*/
  syntax match orgAgendaDay     /^ \(Monday\|Tuesday\|Wednesday\|Thursday\|Friday\|Saturday\|Sunday\).*/
  syntax match orgAgendaToday   /^.*◀ today.*/
  syntax match orgAgendaOverdue /^ Overdue:/
  syntax match orgAgendaEmpty   /^   (nothing.*)/
  syntax match orgAgendaFile    /\S\+\.org:\d\+\s*$/
  syntax match orgAgendaSection /^ \(TODO\|NEXT\|WAITING\|DONE\|CANCELLED\|[A-Z]\+\)\s*$/
  syntax match orgAgendaTime    /^ *\d\{1,2}:\d\{2}/
  syntax match orgAgendaStale   /\d\+d\ze\s\{2}/

  highlight default orgAgendaSep    ctermfg=242 guifg=#504945
  highlight default orgAgendaHeader ctermfg=214 cterm=bold guifg=#d79921 gui=bold
  highlight default orgAgendaHint   ctermfg=242 guifg=#7c6f64
  highlight default orgAgendaDay    ctermfg=109 cterm=bold guifg=#83a598 gui=bold
  highlight default orgAgendaToday  ctermfg=208 cterm=bold guifg=#fe8019 gui=bold
  highlight default orgAgendaOverdue ctermfg=167 cterm=bold guifg=#fb4934 gui=bold
  highlight default orgAgendaEmpty  ctermfg=242 guifg=#7c6f64 cterm=italic gui=italic
  highlight default orgAgendaFile   ctermfg=242 guifg=#7c6f64
  highlight default orgAgendaSection ctermfg=142 cterm=bold guifg=#b8bb26 gui=bold
  highlight default orgAgendaTime    ctermfg=109 guifg=#83a598
  highlight default orgAgendaStale   ctermfg=167 guifg=#fb4934
endfunction

" ── Rendering helpers ─────────────────────────────────────────────────────────

function! s:begin_render() abort
  setlocal modifiable
  silent! %delete _
  let s:ag.link_map = {}
  let s:render_lnum = 0
endfunction

function! s:end_render() abort
  setlocal nomodifiable
endfunction

function! s:put(line) abort
  let s:render_lnum += 1
  if s:render_lnum == 1
    call setline(1, a:line)
  else
    call append(s:render_lnum - 1, a:line)
  endif
endfunction

function! s:put_link(line, file, lnum) abort
  call s:put(a:line)
  let s:ag.link_map[s:render_lnum] = {'file': a:file, 'lnum': a:lnum}
endfunction

function! s:sep(char) abort
  call s:put(' ' . repeat(a:char, 71))
endfunction

function! s:hint() abort
  call s:put(' W week  A day  M month  T todos  D deadlines' .
        \    '    n/p next/prev  . today  q quit')
endfunction

" Short file name for display (basename only)
function! s:fname(path) abort
  return fnamemodify(a:path, ':t')
endfunction

" For repeating tasks showing on a date after their base date, return 'Xd'
" (days outstanding) to fill the time slot. Otherwise return the clock time.
function! s:stale_label(jdn, base_epoch, rep_n, time_str) abort
  if a:rep_n <= 0 || a:base_epoch < 0 | return a:time_str | endif
  let days = a:jdn - s:epoch_to_jdn(a:base_epoch)
  return days > 0 ? days . 'd' : a:time_str
endfunction

" JDN of the most recent occurrence strictly BEFORE {jdn}, or -1 when the base
" date is still in the future. Mirrors s:occurs_on()'s repeat semantics, and is
" what lets a missed repeat keep nagging on today (Emacs org-agenda behaviour).
function! s:last_occurrence(jdn, base_epoch, rep_n, rep_unit) abort
  if a:base_epoch < 0 | return -1 | endif
  let base = s:epoch_to_jdn(a:base_epoch)
  if base >= a:jdn | return -1 | endif
  if a:rep_n <= 0  | return base | endif

  " Fixed-length units: pure arithmetic
  if a:rep_unit ==# 'd' || a:rep_unit ==# 'w'
    let step = a:rep_unit ==# 'w' ? a:rep_n * 7 : a:rep_n
    if step <= 0 | return base | endif
    return base + ((a:jdn - base - 1) / step) * step
  endif

  " Calendar units: walk back from the estimated index
  let b = org#core#jdn_to_ymd(base)
  let c = org#core#jdn_to_ymd(a:jdn)
  if a:rep_unit ==# 'm'
    let i = ((c[0] - b[0]) * 12 + (c[1] - b[1])) / a:rep_n
  elseif a:rep_unit ==# 'y'
    let i = (c[0] - b[0]) / a:rep_n
  else
    return base
  endif
  while i > 0
    if a:rep_unit ==# 'm'
      let tot  = (b[1] - 1) + i * a:rep_n
      let cand = org#core#jdn(b[0] + tot / 12, tot % 12 + 1, b[2])
    else
      let cand = org#core#jdn(b[0] + i * a:rep_n, b[1], b[2])
    endif
    if cand < a:jdn | return cand | endif
    let i -= 1
  endwhile
  return base
endfunction

" Past-due SCHEDULED items that should nag on today: not done, carrying a TODO
" state, and with a missed occurrence behind them. Returns [[item, kind, time]].
" Skips anything already occurring on {jdn} so it is never listed twice.
function! s:past_scheduled(items, jdn) abort
  let out = []
  if !get(g:, 'org_agenda_show_past_scheduled', 1) | return out | endif
  for it in a:items
    if it.scheduled_epoch < 0 || it.is_done || empty(it.state) | continue | endif
    if s:occurs_on(a:jdn, it.scheduled_epoch,
          \ it.scheduled_repeat_n, it.scheduled_repeat_unit)
      continue
    endif
    let last = s:last_occurrence(a:jdn, it.scheduled_epoch,
          \ it.scheduled_repeat_n, it.scheduled_repeat_unit)
    if last < 0 | continue | endif
    call add(out, [it, printf('Sched.%dx', a:jdn - last), it.scheduled_time])
  endfor
  return out
endfunction

" Format an item line:  '   Kind  HH:MM  STATE  Text          file.org:N'
function! s:item_line(kind, time, state, text, file, lnum) abort
  let tm    = empty(a:time) ? '     ' : printf('%5s', a:time)
  let state = empty(a:state) ? '      ' : printf('%-8s', a:state)
  let ref   = s:fname(a:file) . ':' . a:lnum
  let mid   = '  ' . printf('%-10s', a:kind) . tm . '  ' . state . ' ' . a:text
  let pad   = max([1, 72 - len(mid) - len(ref)])
  return mid . repeat(' ', pad) . ref
endfunction

" ── Week view ─────────────────────────────────────────────────────────────────

function! s:render_week(items) abort
  let mon  = s:ag.base_jdn
  let sun  = mon + 6
  let today = s:today_jdn()
  let ymd_mon = org#core#jdn_to_ymd(mon)
  let ymd_sun = org#core#jdn_to_ymd(sun)

  call s:put(' Org Agenda — Week  ' .
        \ s:fmt_day(mon) . ' – ' . s:fmt_day(sun) .
        \ '  ·  W' . printf('%02d', s:iso_week(mon)))
  call s:hint()
  call s:sep('─')

  " Overdue deadlines (deadline_epoch < today midnight)
  let today_epoch = s:jdn_to_epoch(today)
  let overdue = filter(copy(a:items),
        \ {_, v -> v.deadline_epoch >= 0 && v.deadline_epoch < today_epoch
        \       && v.state !=# '' && !v.is_done
        \       && v.deadline_repeat_n <= 0})
  if !empty(overdue)
    call s:put(' Overdue:')
    for it in overdue
      let dl_jdn = s:epoch_to_jdn(it.deadline_epoch)
      let days   = today - dl_jdn
      let label  = 'Deadline'
      let time   = days == 1 ? '1 day ago' : days . ' days ago'
      call s:put_link(s:item_line(label, time, it.state, it.text, it.file, it.lnum),
            \ it.file, it.lnum)
    endfor
    call s:sep('─')
  endif

  " Items that will nag on today: their earlier missed occurrences inside this
  " same week are suppressed below, so an overdue repeat is listed once, not
  " twice. Browsing to another week still shows those occurrences normally.
  let nag_keys = {}
  if today >= mon && today <= sun
    for [nit, nkind, ntime] in s:past_scheduled(a:items, today)
      let nag_keys[nit.file . ':' . nit.lnum] = 1
    endfor
  endif

  " Day-by-day
  for offset in range(7)
    let jdn = mon + offset
    let wd  = jdn % 7
    let ymd = org#core#jdn_to_ymd(jdn)
    let label = printf('%-9s', s:day_names[wd]) . ' ' .
          \ s:month_names[ymd[1]-1][:2] . ' ' . printf('%2d', ymd[2])
    if jdn == today
      call s:put(' ' . label . ' ◀ today')
    else
      call s:put(' ' . label)
    endif

    " Items for this day
    let day_epoch_lo = s:jdn_to_epoch(jdn)
    let day_epoch_hi = day_epoch_lo + 86399

    let day_items = []
    for it in a:items
      if s:occurs_on(jdn, it.scheduled_epoch, it.scheduled_repeat_n, it.scheduled_repeat_unit)
        " Suppressed: this missed occurrence is folded into today's nag line
        if jdn < today && has_key(nag_keys, it.file . ':' . it.lnum) | continue | endif
        let lbl = s:stale_label(jdn, it.scheduled_epoch, it.scheduled_repeat_n, it.scheduled_time)
        call add(day_items, [it, 'Scheduled', lbl])
      elseif s:occurs_on(jdn, it.deadline_epoch, it.deadline_repeat_n, it.deadline_repeat_unit)
        let lbl = s:stale_label(jdn, it.deadline_epoch, it.deadline_repeat_n, it.deadline_time)
        call add(day_items, [it, 'Deadline', lbl])
      endif
    endfor

    " Missed SCHEDULED occurrences keep nagging on today until marked done
    if jdn == today
      call extend(day_items, s:past_scheduled(a:items, jdn))
    endif

    if empty(day_items)
      call s:put('   (nothing scheduled)')
    else
      for [it, kind, time] in day_items
        call s:put_link(s:item_line(kind, time, it.state, it.text, it.file, it.lnum),
              \ it.file, it.lnum)
      endfor
    endif
  endfor
endfunction

" ── Month view ────────────────────────────────────────────────────────────────

function! s:render_month(items) abort
  let focus = s:ag.focus_jdn
  let ymd   = org#core#jdn_to_ymd(focus)
  let y     = ymd[0]
  let m     = ymd[1]
  let today = s:today_jdn()
  let dm    = org#core#days_in_month(y, m)
  let fw    = org#core#jdn(y, m, 1) % 7   " 0=Mon weekday of day 1

  call s:put(' Org Agenda — ' . s:month_names[m-1] . ' ' . y)
  call s:hint()
  call s:sep('─')
  call s:put('      Mo  Tu  We  Th  Fr  Sa  Su')

  " Build grid
  let row = '      ' . repeat('    ', fw)
  let col = fw
  for day in range(1, dm)
    let jdn = org#core#jdn(y, m, day)
    if jdn == focus && jdn == today
      let cell = '[' . printf('%2d', day) . ']*'
    elseif jdn == focus
      let cell = '[' . printf('%2d', day) . '] '
    elseif jdn == today
      let cell = ' ' . printf('%2d', day) . '* '
    else
      let cell = ' ' . printf('%2d', day) . '  '
    endif
    let row .= cell
    let col  += 1
    if col == 7
      call s:put(row[:-2])
      let row = '      '
      let col = 0
    endif
  endfor
  if col > 0
    call s:put(row[:-2])
  endif

  " Items for focused day
  let fwd   = focus % 7
  let fymd  = org#core#jdn_to_ymd(focus)
  call s:put('')
  call s:put(' Items on ' . s:day_short[fwd] . ' ' .
        \ s:month_names[fymd[1]-1][:2] . ' ' . printf('%d', fymd[2]) . ':')

  let day_lo = s:jdn_to_epoch(focus)
  let day_hi = day_lo + 86399
  let found  = 0
  for it in a:items
    if it.scheduled_epoch >= 0 && s:epoch_to_jdn(it.scheduled_epoch) == focus
      call s:put_link(s:item_line('Scheduled', it.scheduled_time,
            \ it.state, it.text, it.file, it.lnum), it.file, it.lnum)
      let found = 1
    endif
    if it.deadline_epoch >= 0 && s:epoch_to_jdn(it.deadline_epoch) == focus
      call s:put_link(s:item_line('Deadline', it.deadline_time,
            \ it.state, it.text, it.file, it.lnum), it.file, it.lnum)
      let found = 1
    endif
  endfor
  if !found
    call s:put('   (nothing scheduled)')
  endif
endfunction

" ── Day view ─────────────────────────────────────────────────────────────────
" Hourly timeline for a single day. Items with a specific time land in their
" slot; items scheduled/deadlined for the day without a time go to All day.

function! s:render_day(items) abort
  let jdn    = s:ag.focus_jdn
  let today  = s:today_jdn()
  let ymd    = org#core#jdn_to_ymd(jdn)
  let wd     = jdn % 7
  let h_start = get(g:, 'org_agenda_day_start', 7)
  let h_end   = get(g:, 'org_agenda_day_end', 22)

  let title = s:day_names[wd] . ' ' . printf('%d', ymd[2]) . ' ' .
        \ s:month_names[ymd[1]-1] . ' ' . ymd[0]
  call s:put(' Org Agenda — Day  ' . title .
        \ (jdn == today ? '  ◀ today' : '') .
        \ '  ·  W' . printf('%02d', s:iso_week(jdn)))
  call s:hint()
  call s:sep('─')

  " Collect items for this day
  let day_lo = s:jdn_to_epoch(jdn)
  let day_hi = day_lo + 86399

  let allday  = []    " items without a specific time
  let timed   = {}    " hour (int) → list of [item, kind, mm]

  for it in a:items
    for [ep, rn, ru, kind, time_str] in [
          \ [it.scheduled_epoch, it.scheduled_repeat_n, it.scheduled_repeat_unit, 'Scheduled', it.scheduled_time],
          \ [it.deadline_epoch,  it.deadline_repeat_n,  it.deadline_repeat_unit,  'Deadline',  it.deadline_time]]
      if !s:occurs_on(jdn, ep, rn, ru) | continue | endif
      let lbl = s:stale_label(jdn, ep, rn, time_str)
      if lbl !=# time_str
        " repeating, past base: land in all-day with the stale label
        call add(allday, [it, kind, lbl])
        continue
      endif
      if time_str !=# ''
        let tm = matchlist(time_str, '^\(\d\{1,2}\):\(\d\{2}\)$')
        if !empty(tm)
          let h = tm[1] + 0
          if !has_key(timed, h)
            let timed[h] = []
          endif
          call add(timed[h], [it, kind, time_str])
          continue
        endif
      endif
      call add(allday, [it, kind, ''])
    endfor
  endfor

  " Also collect overdue deadlines (deadline < today, no done state) and
  " missed SCHEDULED occurrences, which nag on today until marked done.
  if jdn == today
    for it in a:items
      if it.deadline_epoch < 0 | continue | endif
      if it.is_done | continue | endif
      if it.deadline_epoch < day_lo && it.deadline_repeat_n <= 0
        call add(allday, [it, 'Overdue', ''])
      endif
    endfor
    call extend(allday, s:past_scheduled(a:items, jdn))
  endif

  " All-day section
  if !empty(allday)
    call s:put(' All day:')
    for [it, kind, lbl] in allday
      call s:put_link(s:item_line(kind, lbl, it.state, it.text, it.file, it.lnum),
            \ it.file, it.lnum)
    endfor
    call s:sep('─')
  endif

  " Hour slots
  let now_h = (jdn == today) ? strftime('%H', localtime()) + 0 : -1
  for h in range(h_start, h_end)
    let label = printf('%2d:00', h)
    if h == now_h
      let slot_line = ' ' . label . ' ◀ now ' . repeat('─', 55)
    elseif has_key(timed, h)
      let first = timed[h][0]
      let line0 = ' ' . label . '  ' .
            \ s:item_line(first[1], printf('%02d:%02d', h, 0),
            \             first[0].state, first[0].text,
            \             first[0].file, first[0].lnum)
      call s:put_link(line0, first[0].file, first[0].lnum)
      " Additional items in the same hour
      for [it, kind, ts] in timed[h][1:]
        call s:put_link('        ' .
              \ s:item_line(kind, ts, it.state, it.text, it.file, it.lnum),
              \ it.file, it.lnum)
      endfor
      continue
    else
      let slot_line = ' ' . label . ' ' . repeat('─', 62)
    endif
    call s:put(slot_line)
  endfor
endfunction

" ── Todo view ─────────────────────────────────────────────────────────────────

function! s:render_todo(items) abort
  let kw     = s:kw_dict()
  let files  = org#core#agenda_files()
  call s:put(' Org Agenda — All TODOs (' . len(files) . ' file' .
        \ (len(files) == 1 ? '' : 's') . ')')
  call s:hint()
  call s:sep('─')

  " Section order: the global active keywords first, then any file-local
  " active state (REPEAT, MISSED ...) that a scanned file declared itself.
  let states = copy(kw.active)
  for it in a:items
    if !empty(it.state) && !it.is_done && index(states, it.state) < 0
      call add(states, it.state)
    endif
  endfor

  let found = 0
  for state in states
    let grp = filter(copy(a:items), {_, v -> v.state ==# state && !v.is_done})
    if empty(grp) | continue | endif
    " Sort by priority: [#A]=1, [#B]=2, [#C]=3, none=4
    call sort(grp, {a, b ->
          \ (a.priority ==# '' ? 999 : char2nr(a.priority)) -
          \ (b.priority ==# '' ? 999 : char2nr(b.priority))})
    let found = 1
    call s:put(' ' . state)
    for it in grp
      let prio_tag = it.priority !=# '' ? '[#' . it.priority . '] ' : ''
      call s:put_link(s:item_line('', '', state, prio_tag . it.text, it.file, it.lnum),
            \ it.file, it.lnum)
    endfor
  endfor

  if !found
    let configured = get(g:, 'org_agenda_files', [])
    if empty(configured)
      call s:put('   (no files configured — set g:org_agenda_files)')
    elseif empty(files)
      call s:put('   (no .org files found — checked: ' . join(configured, ', ') . ')')
    else
      call s:put('   (no active TODOs found in ' . len(files) . ' file' .
            \ (len(files) == 1 ? '' : 's') . ')')
    endif
  endif
endfunction

" ── Deadlines view ────────────────────────────────────────────────────────────

function! s:render_deadlines(items) abort
  let horizon = get(g:, 'org_agenda_deadline_days', 14)
  call s:put(' Org Agenda — Upcoming Deadlines (' . horizon . ' days)')
  call s:hint()
  call s:sep('─')

  let today    = s:today_jdn()
  let today_ep = s:jdn_to_epoch(today)
  let limit_ep = today_ep + horizon * 86400

  " Separate overdue vs upcoming
  let overdue  = []
  let upcoming = []

  for it in a:items
    if it.deadline_epoch < 0 | continue | endif
    if it.is_done | continue | endif
    let dl_jdn = s:epoch_to_jdn(it.deadline_epoch)
    if dl_jdn < today
      call add(overdue, it)
    elseif it.deadline_epoch <= limit_ep
      call add(upcoming, it)
    endif
  endfor

  " Sort upcoming by deadline epoch
  call sort(upcoming, {a, b -> a.deadline_epoch - b.deadline_epoch})

  if !empty(overdue)
    call s:put(' Overdue:')
    call sort(overdue, {a, b -> a.deadline_epoch - b.deadline_epoch})
    for it in overdue
      let dl_jdn = s:epoch_to_jdn(it.deadline_epoch)
      let days   = today - dl_jdn
      let ago    = days == 1 ? '1 day ago' : days . ' days ago'
      call s:put_link(s:item_line('Deadline', ago, it.state, it.text, it.file, it.lnum),
            \ it.file, it.lnum)
    endfor
    call s:sep('─')
  endif

  if empty(upcoming)
    call s:put('   (no upcoming deadlines within ' . horizon . ' days)')
  else
    for it in upcoming
      let dl_jdn = s:epoch_to_jdn(it.deadline_epoch)
      let days   = dl_jdn - today
      let inf    = days == 0 ? 'today' : days == 1 ? 'in 1 day' : 'in ' . days . ' days'
      let dl_str = s:fmt_day(dl_jdn)
      call s:put_link(s:item_line(dl_str, inf, it.state, it.text, it.file, it.lnum),
            \ it.file, it.lnum)
    endfor
  endif
endfunction

" ── Month-view day navigation ─────────────────────────────────────────────────

function! s:month_move_focus(delta) abort
  let new_jdn = s:ag.focus_jdn + a:delta
  let ymd = org#core#jdn_to_ymd(new_jdn)
  " Update base month if day moved outside current month
  let cur_ymd = org#core#jdn_to_ymd(s:ag.focus_jdn)
  if ymd[0] != cur_ymd[0] || ymd[1] != cur_ymd[1]
    let s:ag.base_jdn = new_jdn
  endif
  let s:ag.focus_jdn = new_jdn
  call org#agenda#refresh()
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

function! org#agenda#refresh() abort
  if s:ag.bufnr == -1 || !bufexists(s:ag.bufnr)
    return
  endif

  let items = s:scan_files()

  call s:begin_render()

  if s:ag.view ==# 'week'
    call s:render_week(items)
  elseif s:ag.view ==# 'day'
    call s:render_day(items)
  elseif s:ag.view ==# 'month'
    call s:render_month(items)
  elseif s:ag.view ==# 'todo'
    call s:render_todo(items)
  elseif s:ag.view ==# 'deadlines'
    call s:render_deadlines(items)
  endif

  call s:end_render()
  call cursor(1, 1)
endfunction

function! org#agenda#next() abort
  if s:ag.view ==# 'week'
    let s:ag.base_jdn += 7
  elseif s:ag.view ==# 'day'
    let s:ag.focus_jdn += 1
  elseif s:ag.view ==# 'month'
    let ymd = org#core#jdn_to_ymd(s:ag.focus_jdn)
    let m = ymd[1] + 1
    let y = ymd[0]
    if m > 12 | let m = 1 | let y += 1 | endif
    let d = min([ymd[2], org#core#days_in_month(y, m)])
    let s:ag.focus_jdn = org#core#jdn(y, m, d)
    let s:ag.base_jdn  = s:ag.focus_jdn
  elseif s:ag.view ==# 'deadlines'
    let g:org_agenda_deadline_days += 7
  endif
  call org#agenda#refresh()
endfunction

function! org#agenda#prev() abort
  if s:ag.view ==# 'week'
    let s:ag.base_jdn -= 7
  elseif s:ag.view ==# 'day'
    let s:ag.focus_jdn -= 1
  elseif s:ag.view ==# 'month'
    let ymd = org#core#jdn_to_ymd(s:ag.focus_jdn)
    let m = ymd[1] - 1
    let y = ymd[0]
    if m < 1 | let m = 12 | let y -= 1 | endif
    let d = min([ymd[2], org#core#days_in_month(y, m)])
    let s:ag.focus_jdn = org#core#jdn(y, m, d)
    let s:ag.base_jdn  = s:ag.focus_jdn
  elseif s:ag.view ==# 'deadlines'
    let g:org_agenda_deadline_days = max([7, g:org_agenda_deadline_days - 7])
  endif
  call org#agenda#refresh()
endfunction

function! org#agenda#today() abort
  let s:ag.base_jdn  = s:week_monday(s:today_jdn())
  let s:ag.focus_jdn = s:today_jdn()
  call org#agenda#refresh()
endfunction

function! org#agenda#set_view(view) abort
  let s:ag.view = a:view
  call org#agenda#refresh()
endfunction

function! org#agenda#cursor_down() abort
  if s:ag.view ==# 'month'
    call s:month_move_focus(+7)
  else
    normal! j
  endif
endfunction

function! org#agenda#cursor_up() abort
  if s:ag.view ==# 'month'
    call s:month_move_focus(-7)
  else
    normal! k
  endif
endfunction

function! org#agenda#cursor_left() abort
  if s:ag.view ==# 'month'
    call s:month_move_focus(-1)
  else
    normal! h
  endif
endfunction

function! org#agenda#cursor_right() abort
  if s:ag.view ==# 'month'
    call s:month_move_focus(+1)
  else
    normal! l
  endif
endfunction

function! org#agenda#jump() abort
  let lnum = line('.')
  if !has_key(s:ag.link_map, lnum)
    return
  endif
  let target = s:ag.link_map[lnum]
  wincmd p
  execute 'edit ' . fnameescape(target.file)
  call cursor(target.lnum, 1)
  normal! zv
endfunction

" Change the TODO state of the item under the cursor in its source file,
" save it, and redraw. dir=1 forward (or shortcut prompt), dir=-1 backward.
function! org#agenda#todo(dir) abort
  let lnum = line('.')
  if !has_key(s:ag.link_map, lnum)
    echo 'org: no item on this line'
    return
  endif
  let target  = s:ag.link_map[lnum]
  let ag_win  = win_getid()

  " Work in the previous window, then put its buffer and view back
  " (or in a temporary split when the agenda is the only window)
  wincmd p
  let tmp_split = win_getid() == ag_win
  if tmp_split
    belowright split
  endif
  let prev_buf  = bufnr('%')
  let prev_view = winsaveview()
  execute 'keepalt hide edit ' . fnameescape(target.file)
  call cursor(target.lnum, 1)
  if a:dir > 0
    call org#todo#cycle()
  else
    call org#todo#cycle_back()
  endif
  silent update
  if tmp_split
    close
  elseif bufnr('%') != prev_buf
    execute 'keepalt hide buffer ' . prev_buf
    call winrestview(prev_view)
  endif

  call win_gotoid(ag_win)
  call org#agenda#refresh()
  call cursor(min([lnum, line('$')]), 1)
endfunction

function! org#agenda#preview() abort
  let lnum = line('.')
  if !has_key(s:ag.link_map, lnum)
    return
  endif
  let target = s:ag.link_map[lnum]
  let cur_win = winnr()
  wincmd p
  execute 'edit ' . fnameescape(target.file)
  call cursor(target.lnum, 1)
  normal! zv
  execute cur_win . 'wincmd w'
endfunction
