" autoload/org/highlight.vim — static highlight group definitions
" Called from syntax/org.vim, ftplugin/org.vim, and the ColorScheme autocmd
" so that colors survive colorscheme reloads and lazy-load plugin init order.

function! org#highlight#apply() abort
  " Headlines — neutral tone for body text; the keyword inside carries the color.
  " Subtle level fade: L1 brightest, deeper levels slightly dimmer.
  highlight orgHeadline1 ctermfg=223 cterm=NONE guifg=#ebdbb2 gui=NONE
  highlight orgHeadline2 ctermfg=248 cterm=NONE guifg=#d5c4a1 gui=NONE
  highlight orgHeadline3 ctermfg=246 cterm=NONE guifg=#bdae93 gui=NONE
  highlight orgHeadline4 ctermfg=246 cterm=NONE guifg=#a89984 gui=NONE
  highlight orgHeadline5 ctermfg=245 cterm=NONE guifg=#a89984 gui=NONE
  highlight orgHeadline6 ctermfg=244 cterm=NONE guifg=#928374 gui=NONE
  highlight orgHeadline7 ctermfg=243 cterm=NONE guifg=#928374 gui=NONE
  highlight orgHeadline8 ctermfg=242 cterm=NONE guifg=#7c6f64 gui=NONE

  " Stars — dim so they don't compete with headline text
  highlight orgStars1 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars2 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars3 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars4 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars5 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars6 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars7 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE
  highlight orgStars8 ctermfg=240 cterm=NONE guifg=#504945 gui=NONE

  " Priority cookies
  highlight orgPriorityA ctermfg=167 cterm=bold guifg=#fb4934 gui=bold
  highlight orgPriorityB ctermfg=208 cterm=bold guifg=#fe8019 gui=bold
  highlight orgPriorityC ctermfg=214 cterm=bold guifg=#fabd2f gui=bold
  highlight orgPriority  ctermfg=246 cterm=bold guifg=#a89984 gui=bold

  " Misc structural elements
  highlight orgTag             ctermfg=109 cterm=NONE guifg=#83a598 gui=NONE
  highlight orgTimestampActive   ctermfg=208 cterm=NONE guifg=#fe8019 gui=NONE
  highlight orgTimestampInactive ctermfg=246 cterm=NONE guifg=#a89984 gui=NONE
  highlight link orgPlanning   Keyword
  highlight orgPropertyKey     ctermfg=109 cterm=NONE guifg=#83a598 gui=NONE
  highlight link orgProperties Special
  highlight link orgLogbook    Special
  highlight orgClockLine       ctermfg=246 cterm=NONE guifg=#a89984 gui=NONE
  highlight orgClockDuration   ctermfg=214 cterm=bold guifg=#fabd2f gui=bold
  highlight link orgBlockBound PreProc
  highlight link orgMetaKey    Keyword
  highlight link orgComment    Comment

  " Inline markup and links
  highlight orgLink     ctermfg=109 cterm=underline guifg=#83a598 gui=underline
  highlight orgBold     ctermfg=222 cterm=bold      guifg=#ffd75f gui=bold
  highlight orgItalic   ctermfg=109 cterm=italic    guifg=#83a598 gui=italic
  highlight orgCode     ctermfg=142 cterm=NONE       guifg=#b8bb26 gui=NONE
  highlight orgVerbatim ctermfg=108 cterm=NONE       guifg=#8ec07c gui=NONE
  highlight orgStrike   ctermfg=244 cterm=NONE       guifg=#928374 gui=strikethrough

  " Lists and checkboxes
  highlight orgListBullet      ctermfg=214 cterm=NONE guifg=#d79921 gui=NONE
  highlight link orgListNum    orgListBullet
  highlight orgCheckboxDone    ctermfg=142 cterm=bold guifg=#b8bb26 gui=bold
  highlight orgCheckboxIndet   ctermfg=214 cterm=bold guifg=#fabd2f gui=bold
  highlight orgCheckboxTodo    ctermfg=246 cterm=NONE guifg=#a89984 gui=NONE
  highlight orgCheckboxSummary ctermfg=108 cterm=NONE guifg=#8ec07c gui=NONE
  highlight link orgHRule      NonText

  " Fold text — override whatever the colorscheme sets so org folds don't
  " appear in whatever bright color the theme chose for Folded.
  highlight Folded ctermfg=245 ctermbg=237 guifg=#928374 guibg=#3c3836 gui=NONE

  " Left border bar: virtual '│ ' shown before every line in a code block.
  " Uses orgBlockBound color (teal) to match the #+BEGIN_SRC / #+END_SRC lines.
  if exists('*prop_type_add')
    if empty(prop_type_get('orgBlockBar'))
      call prop_type_add('orgBlockBar', {'highlight': 'orgBlockBound'})
    else
      call prop_type_change('orgBlockBar', {'highlight': 'orgBlockBound'})
    endif
  endif
endfunction
