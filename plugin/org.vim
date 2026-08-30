if exists('g:loaded_org') | finish | endif
let g:loaded_org = 1

command! OrgTodoCycle     call org#todo#cycle()
command! OrgTodoCycleBack call org#todo#cycle_back()
command! OrgReload        call org#config#reload()
command! OrgClockIn       call org#clock#in()
command! OrgClockOut      call org#clock#out()
command! OrgClockToggle   call org#clock#toggle()
command! OrgClockUpdate    call org#clock#update()
command! OrgClockUpdateAll call org#clock#update_all()
command! OrgPromote       call org#headline#promote()
command! OrgDemote        call org#headline#demote()
command! OrgSchedule      call org#date#schedule()
command! OrgDeadline      call org#date#deadline()
command! OrgAgenda        call org#agenda#open()
command! OrgCheckboxToggle call org#checkbox#toggle()
command! OrgOpenLink       call org#link#open()
command! OrgTags           call org#tags#edit()
command! OrgSetID          call org#id#set()
command! OrgArchive        call org#archive#subtree()
command! OrgCapture        call org#capture#open()
command! OrgClockReport    call org#clockreport#update()
command! OrgCtrlC          call org#dispatch#ctrl_c()

" ── Re-apply org highlights whenever a colorscheme is loaded ─────────────────
augroup org_highlight_guard
  autocmd!
  autocmd ColorScheme * call org#highlight#apply()
augroup END

" ── Re-apply fold matchadd() when an org buffer appears in any window ─────────
" matchadd() is window-local, so splits need their own set of IDs.
augroup org_fold_hl_guard
  autocmd!
  autocmd BufWinEnter * if &filetype ==# 'org' | call org#fold#setup_hl() | endif
augroup END

" ── Block background text-property refresh ───────────────────────────────────
" text properties track text changes automatically, but we need to re-scan to
" add props for newly typed #+BEGIN_* blocks.  Debounce so rapid typing in a
" large file doesn't stall.

let s:bbg_timer = -1
let s:bbg_bnr   = -1

function! s:queue_block_bg() abort
  let s:bbg_bnr = bufnr('%')
  if s:bbg_timer >= 0
    silent! call timer_stop(s:bbg_timer)
  endif
  let s:bbg_timer = timer_start(200, function('s:fire_block_bg'))
endfunction

function! s:fire_block_bg(...) abort
  let s:bbg_timer = -1
  if bufexists(s:bbg_bnr) && getbufvar(s:bbg_bnr, '&filetype') ==# 'org'
    let l:wins = win_findbuf(s:bbg_bnr)
    if !empty(l:wins)
      call win_execute(l:wins[0], 'call org#fold#update_block_bg()')
    endif
  endif
endfunction

augroup org_block_bg
  autocmd!
  autocmd BufWinEnter *             if &filetype ==# 'org' | call org#fold#update_block_bg() | endif
  autocmd TextChanged,InsertLeave * if &filetype ==# 'org' | call s:queue_block_bg() | endif
augroup END

" ── Global mappings (not buffer-local — capture works from any filetype) ──────
if !hasmapto('OrgCapture', 'n')
  let s:cap_l = get(g:, 'org_leader', '\')
  execute 'nnoremap <silent> ' . s:cap_l . 'C  :OrgCapture<CR>'
endif
