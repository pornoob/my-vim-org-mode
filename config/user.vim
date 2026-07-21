" vim-org  ·  user configuration template
" ════════════════════════════════════════════════════════════════════════════
"
" HOW TO USE
" ──────────
"  1. Copy this file to:   ~/.vim/after/plugin/org_user.vim
"                   (Windows) %USERPROFILE%\vimfiles\after\plugin\org_user.vim
"  2. Uncomment and edit the sections you want to change.
"  3. Done.  Vim loads after/plugin/ AFTER all plugins, so your settings
"     always take priority.  Plugin updates will never overwrite this file.
"
" After editing this file inside Vim, run :OrgReload to apply changes
" immediately without restarting.
"
" ════════════════════════════════════════════════════════════════════════════

" ── Custom leader key ────────────────────────────────────────────────────────
"
" Sets the prefix used for all org-mode mappings in org buffers only.
" This is independent of <Leader> and <LocalLeader> so it won't affect
" any other filetype.
"
" Priority: g:org_leader  >  maplocalleader  >  '\'
"
" Examples:
"   let g:org_leader = ','       → ,t  ,T  ,R
"   let g:org_leader = '<Space>' → <Space>t  <Space>T  <Space>R
"
" let g:org_leader = ','

" ── TODO keyword sequence ────────────────────────────────────────────────────
"
" Keywords before '|' are ACTIVE (pending).
" Keywords after  '|' are DONE   (finished).
" {leader}t cycles forward through the full sequence.
" {leader}T cycles backward.
"
" let g:org_todo_keywords = ['TODO', 'NEXT', 'WAITING', '|', 'DONE', 'CANCELLED']

" ── Per-keyword colours ───────────────────────────────────────────────────────
"
" Value can be:
"   a raw highlight spec  →  'ctermfg=196 cterm=bold guifg=#fb4934 gui=bold'
"   an existing group     →  'Error'  or  'Comment'
"
" Keywords not listed here get a colour from the built-in ramp automatically.
" Add any custom keyword here alongside your standard ones.
"
" let g:org_todo_keyword_faces = {
"   \ 'TODO':      'ctermfg=196 cterm=bold  guifg=#fb4934 gui=bold',
"   \ 'NEXT':      'ctermfg=208 cterm=bold  guifg=#fe8019 gui=bold',
"   \ 'WAITING':   'ctermfg=214 cterm=bold  guifg=#fabd2f gui=bold',
"   \ 'DONE':      'ctermfg=142 cterm=italic guifg=#b8bb26 gui=italic',
"   \ 'CANCELLED': 'ctermfg=245 cterm=NONE  guifg=#928374 gui=strikethrough',
"   \ 'SOMEDAY':   'ctermfg=109 cterm=bold  guifg=#83a598 gui=bold',
"   \ }

" ── Headline colours ──────────────────────────────────────────────────────────
"
" Override any headline level.  Omit 'default' so your colour always wins
" over the colorscheme.
"
" highlight orgHeadline1 ctermfg=167 cterm=bold guifg=#cc241d gui=bold
" highlight orgHeadline2 ctermfg=214 cterm=bold guifg=#d79921 gui=bold
" highlight orgHeadline3 ctermfg=142 cterm=bold guifg=#98971a gui=bold
