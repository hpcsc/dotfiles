let mapleader = "\<space>"

" Allow saving of files as sudo when I forgot to start vim using sudo.
cnoremap w!! w !sudo tee > /dev/null % 

cnoremap %% <C-R>=expand("%:p:h") . "/" <CR>

map <leader>ew :e %%
map <leader>es :sp %%
map <leader>ev :vsp %%
map <leader>et :tabe %%

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

nnoremap <silent> <leader>[ :exe "resize " . (winheight(0) * 3/2)<CR>
nnoremap <silent> <leader>] :exe "resize " . (winheight(0) * 2/3)<CR>
nnoremap <silent> <leader>< :exe "vertical resize " . (winwidth(0) * 2/3)<CR>
nnoremap <silent> <leader>> :exe "vertical resize " . (winwidth(0) * 3/2)<CR>
nnoremap <silent> <leader>= :winc =<CR>

noremap <leader>s :OverCommandLine<CR>%s/

" jk to quit insert mode
inoremap jk <esc>

"stop highlighting search
nnoremap <CR> :nohlsearch<CR> 
nnoremap <leader>z za " toggle folding
noremap <leader>w :update<CR>
noremap <leader>q :qa<CR>

" insert newline in normal mode
nnoremap <silent> <leader>y o<Esc>

" Enter to dismiss visual mode
vnoremap <CR> <esc>

" yanking in visual mode leaves cursor at the bottom position
vnoremap y ygv<Esc>


" NERDTree Mappings {{{

nnoremap <leader>m :NERDTreeFind<cr>
nnoremap <leader>t :NERDTreeToggle<cr>

" }}}

" fzf  Mappings {{{

nnoremap <c-b> :Buffers<cr>
nnoremap <c-p> :Files<cr>

" }}}

" LanguageClient Mappings {{{

nnoremap <silent> K :call LanguageClient#textDocument_hover()<CR>
nnoremap <silent> <F12> :call LanguageClient#textDocument_definition()<CR>
nnoremap <silent> <F2> :call LanguageClient#textDocument_rename()<CR>

" }}}

" vim:foldmethod=marker:foldlevel=0
