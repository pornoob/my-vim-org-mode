" autoload/org/table.vim — Org tables: align and move between fields, the way
" Emacs' org-table-align / org-table-next-field do with default settings.

" A table line starts with '|' after optional indentation.
function! s:is_row(line) abort
  return a:line =~# '^\s*|'
endfunction

function! s:is_hline(line) abort
  return a:line =~# '^\s*|-'
endfunction

" 1 when line {lnum} (default: the cursor's) belongs to a table.
function! org#table#at(...) abort
  return s:is_row(getline(a:0 ? a:1 : line('.')))
endfunction

" [first, last] line of the table around {lnum}.
function! s:bounds(lnum) abort
  let [first, last] = [a:lnum, a:lnum]
  while first > 1 && s:is_row(getline(first - 1))
    let first -= 1
  endwhile
  while last < line('$') && s:is_row(getline(last + 1))
    let last += 1
  endwhile
  return [first, last]
endfunction

" Fields of a data row, trimmed: '| a | b |' → ['a', 'b']. A missing final
" '|' is tolerated, as when a row is still being typed.
function! s:fields(line) abort
  let body = substitute(a:line, '^\s*|', '', '')
  let body = substitute(body, '|\s*$', '', '')
  return map(split(body, '|', 1), 'trim(v:val)')
endfunction

" Width Emacs gives a field: links count as their description (or target),
" the way they are displayed; everything else as its display width.
function! s:width(text) abort
  let t = substitute(a:text, '\[\[[^]]*\]\[\([^]]*\)\]\]', '\1', 'g')
  let t = substitute(t, '\[\[\([^]]*\)\]\]', '\1', 'g')
  return strdisplaywidth(t)
endfunction

" Emacs' org-table-number-regexp, simplified: 12, -3.5, 1e3, 10%, 4:30.
function! s:is_number(text) abort
  return a:text =~# '^[<>]\?[-+^.0-9]*\d[-+^.0-9eEdDx()%:]*$'
endfunction

" Align the table around the cursor. Keeps the cursor in the same field.
function! org#table#align() abort
  if !org#table#at()
    return
  endif
  let [row, col] = s:cursor_field()
  let [first, last] = s:bounds(line('.'))
  let lines  = getline(first, last)
  let indent = matchstr(lines[0], '^\s*')

  let rows  = map(copy(lines), 's:is_hline(v:val) ? v:null : s:fields(v:val)')
  let ncols = max(map(filter(copy(rows), 'v:val isnot v:null'), 'len(v:val)'))
  if ncols == 0
    let ncols = 1
  endif

  " Column widths, and right alignment where most non-empty fields are
  " numbers (Emacs' org-table-number-fraction is 0.5)
  let widths = repeat([1], ncols)
  let nums   = repeat([0], ncols)
  let filled = repeat([0], ncols)
  for r in rows
    if r is v:null | continue | endif
    for c in range(len(r))
      let widths[c] = max([widths[c], s:width(r[c])])
      if r[c] !=# ''
        let filled[c] += 1
        let nums[c]   += s:is_number(r[c])
      endif
    endfor
  endfor
  let right = map(range(ncols), 'filled[v:val] > 0 && nums[v:val] * 2 > filled[v:val]')

  let out = []
  for r in rows
    if r is v:null
      call add(out, indent . '|' . join(map(copy(widths), 'repeat("-", v:val + 2)'), '+') . '|')
      continue
    endif
    let cells = []
    for c in range(ncols)
      let text = get(r, c, '')
      let fill = repeat(' ', widths[c] - s:width(text))
      call add(cells, right[c] ? fill . text : text . fill)
    endfor
    call add(out, indent . '| ' . join(cells, ' | ') . ' |')
  endfor

  if out != lines
    call setline(first, out)
  endif
  call s:goto_field(first + row, col)
endfunction

" [row offset from the table's first line, field index] under the cursor.
function! s:cursor_field() abort
  let [first, _] = s:bounds(line('.'))
  let before = strpart(getline('.'), 0, col('.') - 1)
  let col = max([0, len(substitute(before, '[^|]', '', 'g')) - 1])
  return [line('.') - first, col]
endfunction

" Put the cursor at the start of field {col} on line {lnum}: just after the
" '| ' that opens it (on a separator line, at its first dash).
function! s:goto_field(lnum, col) abort
  let line = getline(a:lnum)
  let pos  = -1
  for _ in range(a:col + 1)
    let pos = stridx(line, '|', pos + 1)
    if pos < 0
      return cursor(a:lnum, col([a:lnum, '$']))
    endif
  endfor
  call cursor(a:lnum, min([pos + 3, max([1, len(line)])]))
endfunction

" Align, then move to the next field; from the last field of a row to the
" first of the next data row (separator lines are skipped); from the table's
" last field, open a new row, as Emacs' TAB does.
function! org#table#next_field() abort
  call org#table#align()
  let [first, last] = s:bounds(line('.'))
  let [row, col] = s:cursor_field()
  let ncols = len(s:fields(getline(first + row)))
  if !s:is_hline(getline('.')) && col + 1 < ncols
    return s:goto_field(line('.'), col + 1)
  endif
  let lnum = line('.') + 1
  while lnum <= last && s:is_hline(getline(lnum))
    let lnum += 1
  endwhile
  if lnum > last
    let ncols = max(map(getline(first, last), 's:is_hline(v:val) ? 0 : len(s:fields(v:val))'))
    call append(last, matchstr(getline(first), '^\s*') . '|' . repeat('  |', ncols))
    let lnum = last + 1
    call cursor(lnum, 1)
    call org#table#align()
  endif
  call s:goto_field(lnum, 0)
endfunction

" Align, then move to the previous field (the last field of the previous data
" row from a row's first field). Stays put on the table's first field.
function! org#table#prev_field() abort
  call org#table#align()
  let [first, _] = s:bounds(line('.'))
  let [row, col] = s:cursor_field()
  if !s:is_hline(getline('.')) && col > 0
    return s:goto_field(line('.'), col - 1)
  endif
  let lnum = line('.') - 1
  while lnum >= first && s:is_hline(getline(lnum))
    let lnum -= 1
  endwhile
  if lnum < first
    return s:goto_field(line('.'), 0)
  endif
  call s:goto_field(lnum, len(s:fields(getline(lnum))) - 1)
endfunction

" ── Insert-mode <Tab> / <S-Tab> ───────────────────────────────────────────────
" Inside a table they move between fields; anywhere else they do whatever the
" key did before this buffer mapped it (another plugin's mapping, such as a
" completion accept, or a plain Tab).

" The global insert-mode mapping of key {name} ('Tab' or 'S-Tab'), looked up
" when the key is pressed: plugins such as Codeium map <Tab> on VimEnter, after
" the ftplugin of a file opened from the command line has run. maplist() sees
" global mappings behind this buffer's own; older Vims use what
" org#table#save_fallback() recorded when the ftplugin loaded.
function! s:global_map(name) abort
  if exists('*maplist')
    for m in maplist()
      if !m.buffer && m.mode =~# '[i!]' && m.lhs ==? '<' . a:name . '>'
        return m
      endif
    endfor
    return {}
  endif
  return get(get(b:, 'org_table_fallback', {}), a:name, {})
endfunction

" Record the global insert-mode mapping of key {name} for Vims without
" maplist().
function! org#table#save_fallback(name) abort
  let b:org_table_fallback = get(b:, 'org_table_fallback', {})
  let m = maparg('<' . a:name . '>', 'i', 0, 1)
  let b:org_table_fallback[a:name] = get(m, 'buffer', 0) ? {} : m
endfunction

function! org#table#insert_key(name, dir) abort
  if org#table#at()
    return "\<C-\>\<C-o>:call org#table#" . (a:dir > 0 ? 'next' : 'prev') . "_field()\<CR>"
  endif
  let m = s:global_map(a:name)
  if empty(m)
    return a:name ==# 'Tab' ? "\<Tab>" : "\<S-Tab>"
  endif
  let rhs = substitute(m.rhs, '\c<SID>', '<SNR>' . get(m, 'sid', 0) . '_', 'g')
  if m.expr
    return eval(rhs)
  endif
  let keys = eval('"' . escape(substitute(rhs, '<\([^>]\+\)>', '\\<\1>', 'g'), '"') . '"')
  if m.noremap
    return keys
  endif
  call feedkeys(keys, 'm')
  return ''
endfunction
