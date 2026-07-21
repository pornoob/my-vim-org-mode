" ── Clock report generator ───────────────────────────────────────────────────
" Inserts or updates #+BEGIN: clocktable … #+END: blocks.
" Supported parameters:
"   :scope    file | subtree          (default: file)
"   :maxlevel N                       (default: 3)
"   :block    today | thisweek | lastweek | thismonth | lastmonth
"   :tstart   [YYYY-MM-DD ...]
"   :tend     [YYYY-MM-DD ...]

" ── Timestamp / epoch helpers ─────────────────────────────────────────────────

function! s:ts_to_epoch(ts) abort
  let m = matchlist(a:ts,
    \ '\[\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)\s\S\+\s\+\(\d\{1,2}\):\(\d\{2}\)\]')
  if !empty(m)
    let base = org#core#jdn(1970, 1, 1)
    return (org#core#jdn(m[1]+0, m[2]+0, m[3]+0) - base) * 86400
          \ + (m[4]+0) * 3600 + (m[5]+0) * 60
  endif
  let m2 = matchlist(a:ts, '\[\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)')
  if !empty(m2)
    let base = org#core#jdn(1970, 1, 1)
    return (org#core#jdn(m2[1]+0, m2[2]+0, m2[3]+0) - base) * 86400
  endif
  return -1
endfunction

function! s:today_epoch() abort
  let t = localtime()
  let [y, mo, d] = [strftime('%Y', t)+0, strftime('%m', t)+0, strftime('%d', t)+0]
  return (org#core#jdn(y, mo, d) - org#core#jdn(1970, 1, 1)) * 86400
endfunction

function! s:block_range(block) abort
  if a:block ==# '' | return [-1, -1] | endif
  let t   = localtime()
  let y   = strftime('%Y', t) + 0
  let mo  = strftime('%m', t) + 0
  let d   = strftime('%d', t) + 0
  let jdn = org#core#jdn(y, mo, d)
  let base = org#core#jdn(1970, 1, 1)

  if a:block ==# 'today'
    let s = (jdn - base) * 86400
    return [s, s + 86399]

  elseif a:block ==# 'thisweek'
    let mon = jdn - (jdn % 7)          " Monday (JDN % 7 == 0 → Mon)
    let s = (mon - base) * 86400
    return [s, s + 7 * 86400 - 1]

  elseif a:block ==# 'lastweek'
    let mon = jdn - (jdn % 7) - 7
    let s = (mon - base) * 86400
    return [s, s + 7 * 86400 - 1]

  elseif a:block ==# 'thismonth'
    let s = (org#core#jdn(y, mo, 1) - base) * 86400
    let nmo = mo == 12 ? 1 : mo + 1
    let ny  = mo == 12 ? y + 1 : y
    let e = (org#core#jdn(ny, nmo, 1) - base) * 86400 - 1
    return [s, e]

  elseif a:block ==# 'lastmonth'
    let pmo = mo == 1 ? 12 : mo - 1
    let py  = mo == 1 ? y - 1 : y
    let s = (org#core#jdn(py, pmo, 1) - base) * 86400
    let e = (org#core#jdn(y, mo, 1) - base) * 86400 - 1
    return [s, e]
  endif

  return [-1, -1]
endfunction

" ── Parameter parsing ─────────────────────────────────────────────────────────

function! s:parse_params(line) abort
  let p = {'scope': 'file', 'maxlevel': 3, 'block': '', 'tstart': -1, 'tend': -1}

  let v = matchstr(a:line, ':scope\s\+\zs\S\+')
  if v !=# '' | let p.scope = v | endif

  let v = matchstr(a:line, ':maxlevel\s\+\zs\d\+')
  if v !=# '' | let p.maxlevel = v + 0 | endif

  let v = matchstr(a:line, ':block\s\+\zs\S\+')
  if v !=# '' | let p.block = v | endif

  let v = matchstr(a:line, ':tstart\s\+\zs\[[^\]]*\]')
  if v !=# '' | let p.tstart = s:ts_to_epoch(v) | endif

  let v = matchstr(a:line, ':tend\s\+\zs\[[^\]]*\]')
  if v !=# '' | let p.tend = s:ts_to_epoch(v) | endif

  return p
endfunction

" ── Clock line parsing ────────────────────────────────────────────────────────

function! s:parse_clock(line) abort
  " Closed: CLOCK: [start]--[end] => H:MM  →  {start_epoch, minutes}
  let m = matchlist(a:line,
    \ 'CLOCK:\s*\(\[[^\]]*\]\)--\[[^\]]*\]\s*=>\s*\(\d\+\):\(\d\+\)')
  if !empty(m)
    return {'start': s:ts_to_epoch(m[1]), 'minutes': m[2]*60 + m[3]+0}
  endif
  " Open: CLOCK: [start]
  let m2 = matchlist(a:line, 'CLOCK:\s*\(\[[^\]]*\]\)\s*$')
  if !empty(m2)
    let ep = s:ts_to_epoch(m2[1])
    if ep < 0 | return {} | endif
    return {'start': ep, 'minutes': (localtime() - ep) / 60}
  endif
  return {}
endfunction

" ── Headline text cleanup ─────────────────────────────────────────────────────

function! s:clean_text(raw) abort
  let t = a:raw
  " Strip TODO keyword
  let kws = org#core#keywords().all
  if !empty(kws)
    let t = substitute(t, '^\C\%(' . join(kws, '\|') . '\)\s\+', '', '')
  endif
  " Strip priority
  let t = substitute(t, '^\[#.\]\s*', '', '')
  " Strip tags at end
  let t = substitute(t, '\s\+:[a-zA-Z0-9_@#%:]\+:\s*$', '', '')
  return t
endfunction

" ── Scanning ─────────────────────────────────────────────────────────────────

function! s:scan(lines, params) abort
  let [rs, re] = a:params.block !=# ''
    \ ? s:block_range(a:params.block)
    \ : [a:params.tstart, a:params.tend]

  " Pass 1: build flat node list {level, text, minutes}
  let nodes  = []
  let cur_hl = -1

  for line in a:lines
    let stars = matchstr(line, '^\*\+')
    if !empty(stars)
      call add(nodes, {
        \ 'level':   len(stars),
        \ 'text':    s:clean_text(matchstr(line, '^\*\+\s\+\zs.*')),
        \ 'minutes': 0})
      let cur_hl = len(nodes) - 1
    elseif cur_hl >= 0 && line =~# '\s*CLOCK:'
      let clk = s:parse_clock(line)
      if !empty(clk) && clk.start >= 0
        if rs >= 0 && clk.start < rs | continue | endif
        if re >= 0 && clk.start > re | continue | endif
        let nodes[cur_hl].minutes += clk.minutes
      endif
    endif
  endfor

  " Pass 2: roll up minutes from children → parent
  for i in range(len(nodes) - 1, 0, -1)
    if nodes[i].level <= 1 | continue | endif
    for j in range(i - 1, 0, -1)
      if nodes[j].level < nodes[i].level
        let nodes[j].minutes += nodes[i].minutes
        break
      endif
    endfor
  endfor

  " Pass 3: keep only entries within maxlevel that have time
  return filter(nodes, {_, v -> v.level <= a:params.maxlevel && v.minutes > 0})
endfunction

" ── Rendering ─────────────────────────────────────────────────────────────────

function! s:fmt_dur(min) abort
  return printf('%d:%02d', a:min / 60, a:min % 60)
endfunction

function! s:render(entries, params) abort
  let now = strftime('[%Y-%m-%d %a %H:%M]', localtime())
  let lines = ['#+CAPTION: Clock summary at ' . now]

  if empty(a:entries)
    call extend(lines, [
      \ '| Headline | Time |',
      \ '|----------+------|',
      \ '| /No clocked time/ | 0:00 |'])
    return lines
  endif

  " Grand total = sum of root-level entries (they already include descendants)
  let total = 0
  for e in a:entries
    if e.level == 1 | let total += e.minutes | endif
  endfor
  " Edge case: if scope=subtree the top entry might not be level 1
  if total == 0 && !empty(a:entries)
    let min_level = min(map(copy(a:entries), 'v:val.level'))
    for e in a:entries
      if e.level == min_level | let total += e.minutes | endif
    endfor
  endif

  " Compute column widths
  let w_hl = len('Headline')
  for e in a:entries
    let w = (e.level - 1) * 2 + (e.level > 1 ? 3 : 0) + len(e.text)
    if w > w_hl | let w_hl = w | endif
  endfor
  let w_hl = max([w_hl, len('*Total*')])
  let w_t  = max([len('Time'), len(s:fmt_dur(total)) + 2])  " +2 for bold stars

  let sep = '|' . repeat('-', w_hl + 2) . '+' . repeat('-', w_t + 2) . '|'
  call add(lines, '| ' . printf('%-*s', w_hl, 'Headline')
        \ . ' | ' . printf('%*s', w_t, 'Time') . ' |')
  call add(lines, sep)

  let total_s = '*' . s:fmt_dur(total) . '*'
  call add(lines, '| ' . printf('%-*s', w_hl, '*Total*')
        \ . ' | ' . printf('%*s', w_t, total_s) . ' |')
  call add(lines, sep)

  for e in a:entries
    let indent = repeat('  ', e.level - 1)
    let prefix = e.level > 1 ? '\_ ' : ''
    let label  = indent . prefix . e.text
    let dur    = s:fmt_dur(e.minutes)
    call add(lines, '| ' . printf('%-*s', w_hl, label)
          \ . ' | ' . printf('%*s', w_t, dur) . ' |')
  endfor

  return lines
endfunction

" ── Subtree bounds ────────────────────────────────────────────────────────────

function! s:subtree_lines() abort
  let lnum = line('.')
  while lnum > 0 && getline(lnum) !~# '^\*'
    let lnum -= 1
  endwhile
  if lnum == 0 | return getline(1, line('$')) | endif
  let level = len(matchstr(getline(lnum), '^\*\+'))
  let last = lnum + 1
  while last <= line('$')
    if getline(last) =~# '^\*\+' && len(matchstr(getline(last), '^\*\+')) <= level
      break
    endif
    let last += 1
  endwhile
  return getline(lnum, last - 1)
endfunction

" ── Public API ────────────────────────────────────────────────────────────────

function! org#clockreport#update() abort
  let lnum = line('.')

  " Search backward for the nearest #+BEGIN: clocktable
  let begin_lnum = -1
  let end_lnum   = -1
  for l in range(lnum, max([1, lnum - 300]), -1)
    let gl = getline(l)
    if gl =~? '^#+BEGIN:\s*clocktable'
      let begin_lnum = l | break
    endif
    if gl =~? '^#+END:' && l < lnum | break | endif
  endfor

  " Search forward for #+END:
  if begin_lnum >= 0
    for l in range(begin_lnum + 1, min([line('$'), begin_lnum + 500]))
      if getline(l) =~? '^#+END:'
        let end_lnum = l | break
      endif
    endfor
  endif

  let begin_line = begin_lnum >= 0
    \ ? getline(begin_lnum)
    \ : '#+BEGIN: clocktable :scope file :maxlevel 3'
  let params = s:parse_params(begin_line)

  let scan_lines = params.scope ==# 'subtree'
    \ ? s:subtree_lines()
    \ : getline(1, line('$'))

  let entries = s:scan(scan_lines, params)
  let report  = s:render(entries, params)

  if begin_lnum >= 0 && end_lnum >= 0
    " Replace existing content between BEGIN and END
    let del_s = begin_lnum + 1
    let del_e = end_lnum - 1
    if del_e >= del_s
      execute del_s . ',' . del_e . 'delete _'
      let end_lnum -= (del_e - del_s + 1)
    endif
    call append(begin_lnum, report)
  else
    " Insert a new block below the cursor
    call append(lnum - 1, [begin_line] + report + ['#+END:'])
  endif

  echo 'org: clock report updated'
endfunction
