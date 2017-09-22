let mapleader = ","

" disable arrow navigation keys :(
noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>

noremap <silent> <leader>h :wincmd h<CR>
noremap <silent> <leader>j :wincmd j<CR>
noremap <silent> <leader>k :wincmd k<CR>
noremap <silent> <leader>l :wincmd l<CR>
noremap <silent> <leader>ws :wincmd s<CR>
noremap <silent> <leader>wv :wincmd v<CR>
noremap <silent> <leader>wc :wincmd c<CR>
noremap <leader>s :update<CR>
nnoremap <leader><space> :nohlsearch<CR> "stop highlighting search
nnoremap <leader>z za " toggle folding
inoremap jk <esc>

" NERDTree Mappings {{{

nnoremap <leader>n :NERDTreeToggle<cr>

" }}}

" CtrlP Mappings {{{

nnoremap <c-b> :CtrlPBuffer<cr>
nnoremap <c-p> :CtrlP .<cr>
nnoremap <leader>fF :execute ":CtrlP " . expand('%:p:h')<cr>

" }}}

" Easymotion Mappings {{{
" }}}

" vim:foldmethod=marker:foldlevel=0
