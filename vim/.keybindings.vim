let mapleader = ","
noremap <silent> <leader>h :wincmd h<CR>
noremap <silent> <leader>j :wincmd j<CR>
noremap <silent> <leader>k :wincmd k<CR>
noremap <silent> <leader>l :wincmd l<CR>
noremap <silent> <leader>sb :wincmd p<CR>
noremap <leader>s :update<CR>
nnoremap <leader><space> :nohlsearch<CR> "stop highlighting search
nnoremap <leader>z za " toggle folding
inoremap jk <esc>

"-----------------------------------------------------------------------------
" NERDTree Settings
"-----------------------------------------------------------------------------
nnoremap <leader>n :NERDTreeToggle<cr>


"-----------------------------------------------------------------------------
"" CtrlP Settings
"-----------------------------------------------------------------------------
"
nnoremap <c-b> :CtrlPBuffer<cr>
nnoremap <c-p> :CtrlP .<cr>
nnoremap <leader>fF :execute ":CtrlP " . expand('%:p:h')<cr>
