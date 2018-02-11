" David Nguyen's .vimrc

" Vim Settings {{{

set nocompatible " turn off vi compatibility
set cursorline " highlight current line
set tabstop=2 " number of visual spaces per TAB
set softtabstop=2 " number of spaces in tab when editing
set shiftwidth=2 " number of spaces when indenting with '>'
set expandtab " tabs are spaces
set wildmenu " visual autocomplete for command menu
set lazyredraw " redraw only when we need
set showmatch " highlight matching [{()}]
set incsearch " search as characters are entered
set hlsearch " highlight matches
set foldenable " enable folding
set foldlevelstart=10 " open most folds by default
set foldnestmax=10 " 10 nested fold max
set modelines=1 " enable modeline at the bottom of the file
set hidden " hide current unsaved buffer when opening a new file instead of closing it
set backspace=indent,eol,start
set number relativenumber " show relative line number by default
set clipboard=unnamed " yank to clipboard
set showcmd " show incomplete command
set autoindent " copy indent from current line when starting a new line
set smartindent " indent based on code syntax
set nowrap " not wrap lines
set linebreak " wrap lines at convenient points
set foldmethod=syntax " fold based on filetype syntax
set encoding=utf-8 " to fix NERDTree rendering issue in ubuntu
set backupdir=~/.vim/tmp/backup// " set custom location for backup files
set directory=~/.vim/tmp/swap// " set custom location for swap files
set undodir=~/.vim/tmp/undo// " set custom location for undo files
color slate

augroup numbertoggle
    " set absolute line number in insert mode, hybrid line number otherwise
    autocmd!
    autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
    autocmd BufLeave,FocusLost,InsertEnter * set norelativenumber
augroup end

filetype plugin indent on " load filetype-specific indent files at ~/.vim/indent/*.vim
autocmd FileType cs setlocal tabstop=4 shiftwidth=4 softtabstop=4 expandtab " use 4 spaces indentation for C# files

syntax on

" change highlight background color when using vimdiff as git difftool
highlight DiffChange   cterm=bold   gui=none    ctermfg=NONE          ctermbg=60
highlight DiffText   cterm=bold   gui=none    ctermfg=NONE          ctermbg=52
highlight DiffDelete   cterm=bold   gui=none    ctermfg=NONE          ctermbg=89
highlight DiffAdd   cterm=bold    gui=none    ctermfg=NONE          ctermbg=49

" }}}

" VimPlug {{{
call plug#begin('~/.vim/plugged')

Plug 'scrooloose/nerdtree', { 'on':  'NERDTreeToggle' }
Plug 'vim-airline/vim-airline'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'vim-syntastic/syntastic'
Plug 'tpope/vim-commentary'
Plug 'mileszs/ack.vim'
Plug 'tpope/vim-fugitive'
Plug 'christoomey/vim-tmux-navigator'
Plug 'SirVer/ultisnips'

call plug#end()
" }}}

" Custom Keybindings {{{

source ~/.keybindings.vim

" }}}

" fzf Settings {{{

if executable('rg')
  " Use rg over Grep
  set grepprg=rg\ --vimgrep
endif

" }}}

" Ack.Vim Settings {{{

let g:ackprg = 'rg --vimgrep --no-heading'

" }}}

" Syntastic Settings {{{

set statusline+=%#warningmsg#
set statusline+=%{SyntasticStatuslineFlag()}
set statusline+=%*

let g:syntastic_haskell_checkers = ['hdevtools', 'hlint', 'ghc_mod']
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 0

" }}}

" NERDTree Settings {{{

let NERDTreeShowHidden=1
autocmd StdinReadPre * let s:std_in=1
autocmd VimEnter * if argc() == 1 && isdirectory(argv()[0]) && !exists("s:std_in") | exe 'NERDTree' argv()[0] | wincmd p | ene | endif

" }}}

" Ultisnips Settings {{{

let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-n>"
let g:UltiSnipsJumpBackwardTrigger="<c-p>"
let g:UltiSnipsSnippetDir="~/.vim/UltiSnips"
let g:UltiSnipsSnippetDirectories=["~/.vim/UltiSnips", "UltiSnips"]

" }}}

" vim:foldmethod=marker:foldlevel=0