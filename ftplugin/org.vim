if exists('b:did_ftplugin') | finish | endif
let b:did_ftplugin = 1

" ── Leader resolution ─────────────────────────────────────────────────────────
" Priority: g:org_leader  >  maplocalleader  >  '\'
if exists('g:org_leader')
  let s:l = g:org_leader
elseif exists('g:maplocalleader')
  let s:l = g:maplocalleader
else
  let s:l = '\'
endif

" ── Folding ───────────────────────────────────────────────────────────────────
setlocal foldmethod=expr
setlocal foldexpr=org#fold#expr(v:lnum)
setlocal foldtext=org#fold#text()
setlocal foldlevel=99

" ── Text display ──────────────────────────────────────────────────────────────
setlocal wrap linebreak textwidth=0
setlocal conceallevel=2 concealcursor=nc

" ── TODO cycling ──────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 't  :call org#todo#cycle()<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'T  :call org#todo#cycle_back()<CR>'

" ── Folding keys ──────────────────────────────────────────────────────────────
nnoremap <buffer> <silent> <Tab>   :call org#fold#tab()<CR>
nnoremap <buffer> <silent> <S-Tab> :call org#fold#shifttab()<CR>
execute 'nnoremap <buffer> <silent> ' . s:l . 'f  :call org#fold#toggle_all()<CR>'

" ── Reload ────────────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 'R  :OrgReload<CR>'

" ── Clock ─────────────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 'ci :OrgClockIn<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'co :OrgClockOut<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'cc :OrgClockToggle<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'cr :OrgClockReport<CR>'
" ── Generic context update (Emacs org-mode's C-c C-c) ────────────────────────
nnoremap <buffer> <silent> <C-c><C-c> :OrgCtrlC<CR>

" ── Schedule / Deadline ──────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 's  :OrgSchedule<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'd  :OrgDeadline<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . 'a  :OrgAgenda<CR>'

" ── Promote / Demote ──────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . '<  :OrgPromote<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . '>  :OrgDemote<CR>'
execute 'vnoremap <buffer> <silent> ' . s:l . '<  :<C-u>call org#headline#shift_visual(-1)<CR>'
execute 'vnoremap <buffer> <silent> ' . s:l . '>  :<C-u>call org#headline#shift_visual(1)<CR>'

" ── Checkbox ────────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 'x  :OrgCheckboxToggle<CR>'
execute 'vnoremap <buffer> <silent> ' . s:l . 'x  :<C-u>call org#checkbox#toggle_visual()<CR>'

" ── Open links ────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 'o  :OrgOpenLink<CR>'
nnoremap <buffer> <silent> <CR> :OrgOpenLink<CR>

" ── Priority ──────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . ',  :call org#priority#cycle()<CR>'
execute 'nnoremap <buffer> <silent> ' . s:l . ';  :call org#priority#cycle_back()<CR>'

" ── Tags ──────────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . ':  :OrgTags<CR>'

" ── ID property ───────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . 'i  :OrgSetID<CR>'

" ── Archive ───────────────────────────────────────────────────────────────
execute 'nnoremap <buffer> <silent> ' . s:l . '$  :OrgArchive<CR>'

" ── Highlight groups (applied here so they survive colorscheme reloads) ───────
" Syntax/org.vim sets them first; this re-applies unconditionally so that a
" colorscheme that fires after syntax (lazy-load, VimEnter, etc.) can't wipe them.
call org#highlight#apply()

" ── Fold text highlights ──────────────────────────────────────────────────────
" matchadd() reaches fold text lines (window-level highlight); this is the only
" way to colour foldtext in Vim — the List return API is Neovim-only.
call org#fold#setup_hl()


" ── Cleanup (b:undo_ftplugin is executed on filetype change or OrgReload) ─────
" Embed the resolved leader directly so the unmap uses the right key.
let b:undo_ftplugin =
  \ 'setlocal foldmethod< foldexpr< foldtext< foldlevel<'
  \ . ' wrap< linebreak< textwidth< conceallevel< concealcursor<'
  \ . '| silent! nunmap <buffer> <Tab>'
  \ . '| silent! nunmap <buffer> <S-Tab>'
  \ . '| silent! nunmap <buffer> ' . s:l . 'f'
  \ . '| silent! nunmap <buffer> ' . s:l . 't'
  \ . '| silent! nunmap <buffer> ' . s:l . 'T'
  \ . '| silent! nunmap <buffer> ' . s:l . 'R'
  \ . '| silent! nunmap <buffer> ' . s:l . 's'
  \ . '| silent! nunmap <buffer> ' . s:l . 'd'
  \ . '| silent! nunmap <buffer> ' . s:l . 'a'
  \ . '| silent! nunmap <buffer> ' . s:l . 'ci'
  \ . '| silent! nunmap <buffer> ' . s:l . 'co'
  \ . '| silent! nunmap <buffer> ' . s:l . 'cc'
  \ . '| silent! nunmap <buffer> ' . s:l . 'cr'
  \ . '| silent! nunmap <buffer> ' . s:l . '<'
  \ . '| silent! nunmap <buffer> ' . s:l . '>'
  \ . '| silent! vunmap <buffer> ' . s:l . '<'
  \ . '| silent! vunmap <buffer> ' . s:l . '>'
  \ . '| silent! nunmap <buffer> ' . s:l . 'x'
  \ . '| silent! vunmap <buffer> ' . s:l . 'x'
  \ . '| silent! nunmap <buffer> ' . s:l . 'o'
  \ . '| silent! nunmap <buffer> <CR>'
  \ . '| silent! nunmap <buffer> ' . s:l . ','
  \ . '| silent! nunmap <buffer> ' . s:l . ';'
  \ . '| silent! nunmap <buffer> ' . s:l . ':'
  \ . '| silent! nunmap <buffer> ' . s:l . 'i'
  \ . '| silent! nunmap <buffer> ' . s:l . '$'
  \ . '| call org#fold#clear_hl()'
