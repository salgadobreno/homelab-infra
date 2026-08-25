let SessionLoad = 1
let s:so_save = &g:so | let s:siso_save = &g:siso | setg so=0 siso=0 | setl so=-1 siso=-1
let v:this_session=expand("<sfile>:p")
doautoall SessionLoadPre
silent only
silent tabonly
cd /mnt/sda8/Projects/buzaga/homelab-infra
if expand('%') == '' && !&modified && line('$') <= 1 && getline(1) == ''
  let s:wipebuf = bufnr('%')
endif
let s:shortmess_save = &shortmess
set shortmess+=aoO
badd +103 term:///mnt/sda8/Projects/buzaga/homelab-infra//3322116:/bin/bash
badd +181 term:///mnt/sda8/Projects/buzaga/homelab-infra//3326349:/bin/bash
badd +17 LEARNINGS.md
badd +470 Makefile
badd +3753 term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash
badd +1 tofu/main.tf
badd +72 openspec/changes/bootstrap-k3s-node/tasks.md
badd +1 openspec/changes/bootstrap-k3s-node/proposal.md
badd +31 openspec/changes/bootstrap-k3s-node/design.md
badd +97 openspec/changes/bootstrap-k3s-node/specs/infrastructure/k3s-cluster/spec.md
badd +1 openspec/changes/bootstrap-k3s-node/specs/infrastructure/vm-provisioning/spec.md
badd +27 tofu/cloud-init/user-data.yaml.tftpl
badd +131 term:///mnt/sda8/Projects/buzaga/homelab-infra//3413598:/bin/bash
badd +0 .claude/commands/opsx/explore.md
badd +34 FUNDAMENTALS.md
badd +1 kubeconfig
badd +13 tofu/.terraform/providers/registry.opentofu.org/bpg/proxmox/0.111.1/linux_amd64/README.md
badd +1 tofu/terraform.tfvars
badd +19 tofu/terraform.tfstate
badd +4 tofu/outputs.tf
badd +1 LEARNINGS/README.md
badd +19 LEARNINGS/queue.md
badd +1 openspec/config.yaml
badd +1 openspec/specs/infrastructure/vm-provisioning/spec.md
badd +37 LEARNINGS/terraform/101-basics.md
badd +1 scripts/create-snippet-user.sh
badd +1 scripts/withdraw-root-key.sh
badd +41 scripts/harden-cloudflared.sh
badd +15 openspec/specs/infrastructure/k3s-cluster/spec.md
badd +121 LEARNINGS/argocd/101-basics.md
badd +1 README.md
badd +1 openspec/changes/archive/2026-08-21-bootstrap-k3s-node/design.md
badd +120 CLAUDE.md
badd +21 /mnt/sda8/Projects/buzaga/homelab-infra/openspec/changes/archive/2026-08-25-show-the-machine/baseline.md
badd +124 /mnt/sda8/Projects/buzaga/homelab-infra/openspec/changes/archive/2026-08-25-show-the-machine/design.md
badd +64 /mnt/sda8/Projects/buzaga/homelab-infra/openspec/changes/archive/2026-08-25-show-the-machine/proposal.md
badd +40 /mnt/sda8/Projects/buzaga/homelab-infra/openspec/changes/archive/2026-08-25-show-the-machine/tasks.md
badd +56 openspec/specs/infrastructure/site-delivery/spec.md
badd +45 /mnt/sda8/Projects/buzaga/homelab-infra/openspec/changes/archive/2026-08-25-show-the-machine/specs/infrastructure/self-description/spec.md
badd +13 k8s/site/content/machine.html
badd +11 /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/content/index.html
badd +6 /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/parts/intro.html
badd +65 term:///mnt/sda8/Projects/buzaga/homelab-infra//718677:/bin/bash
badd +19 /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/parts/architecture.html
argglobal
%argdel
tabnew +setlocal\ bufhidden=wipe
tabnew +setlocal\ bufhidden=wipe
tabnew +setlocal\ bufhidden=wipe
tabnew +setlocal\ bufhidden=wipe
tabrewind
edit /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/parts/intro.html
let s:save_splitbelow = &splitbelow
let s:save_splitright = &splitright
set splitbelow splitright
wincmd _ | wincmd |
vsplit
1wincmd h
wincmd w
let &splitbelow = s:save_splitbelow
let &splitright = s:save_splitright
wincmd t
let s:save_winminheight = &winminheight
let s:save_winminwidth = &winminwidth
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
exe 'vert 1resize ' . ((&columns * 67 + 67) / 135)
exe 'vert 2resize ' . ((&columns * 67 + 67) / 135)
argglobal
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 1 - ((0 * winheight(0) + 14) / 28)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 1
normal! 061|
wincmd w
argglobal
if bufexists(fnamemodify("term:///mnt/sda8/Projects/buzaga/homelab-infra//3322116:/bin/bash", ":p")) | buffer term:///mnt/sda8/Projects/buzaga/homelab-infra//3322116:/bin/bash | else | edit term:///mnt/sda8/Projects/buzaga/homelab-infra//3322116:/bin/bash | endif
if &buftype ==# 'terminal'
  silent file term:///mnt/sda8/Projects/buzaga/homelab-infra//3322116:/bin/bash
endif
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 103 - ((16 * winheight(0) + 14) / 29)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 103
normal! 023|
wincmd w
2wincmd w
exe 'vert 1resize ' . ((&columns * 67 + 67) / 135)
exe 'vert 2resize ' . ((&columns * 67 + 67) / 135)
tabnext
edit /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/content/index.html
let s:save_splitbelow = &splitbelow
let s:save_splitright = &splitright
set splitbelow splitright
wincmd _ | wincmd |
vsplit
1wincmd h
wincmd w
let &splitbelow = s:save_splitbelow
let &splitright = s:save_splitright
wincmd t
set winminheight=0
set winheight=1
set winminwidth=0
set winwidth=1
exe 'vert 1resize ' . ((&columns * 30 + 67) / 135)
exe 'vert 2resize ' . ((&columns * 104 + 67) / 135)
argglobal
enew
file neo-tree\ filesystem\ \[7]
balt Makefile
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
wincmd w
argglobal
balt /mnt/sda8/Projects/buzaga/homelab-infra/k8s/site/parts/intro.html
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
2
sil! normal! zo
3
sil! normal! zo
let s:l = 11 - ((10 * winheight(0) + 15) / 30)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 11
normal! 06|
wincmd w
exe 'vert 1resize ' . ((&columns * 30 + 67) / 135)
exe 'vert 2resize ' . ((&columns * 104 + 67) / 135)
tabnext
edit LEARNINGS/argocd/101-basics.md
argglobal
balt tofu/main.tf
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 121 - ((27 * winheight(0) + 15) / 30)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 121
normal! 0
tabnext
argglobal
if bufexists(fnamemodify("term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash", ":p")) | buffer term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash | else | edit term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash | endif
if &buftype ==# 'terminal'
  silent file term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash
endif
balt Makefile
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 3768 - ((22 * winheight(0) + 15) / 31)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 3768
normal! 071|
tabnext
argglobal
if bufexists(fnamemodify("term:///mnt/sda8/Projects/buzaga/homelab-infra//718677:/bin/bash", ":p")) | buffer term:///mnt/sda8/Projects/buzaga/homelab-infra//718677:/bin/bash | else | edit term:///mnt/sda8/Projects/buzaga/homelab-infra//718677:/bin/bash | endif
if &buftype ==# 'terminal'
  silent file term:///mnt/sda8/Projects/buzaga/homelab-infra//718677:/bin/bash
endif
balt term:///mnt/sda8/Projects/buzaga/homelab-infra//3347696:/bin/bash
setlocal foldmethod=expr
setlocal foldexpr=v:lua.require'astroui.folding'.foldexpr()
setlocal foldmarker={{{,}}}
setlocal foldignore=#
setlocal foldlevel=99
setlocal foldminlines=1
setlocal foldnestmax=20
setlocal foldenable
let s:l = 57 - ((20 * winheight(0) + 14) / 29)
if s:l < 1 | let s:l = 1 | endif
keepjumps exe s:l
normal! zt
keepjumps 57
normal! 071|
tabnext 1
if exists('s:wipebuf') && len(win_findbuf(s:wipebuf)) == 0 && getbufvar(s:wipebuf, '&buftype') isnot# 'terminal'
  silent exe 'bwipe ' . s:wipebuf
endif
unlet! s:wipebuf
set winheight=1 winwidth=20
let &shortmess = s:shortmess_save
let &winminheight = s:save_winminheight
let &winminwidth = s:save_winminwidth
let s:sx = expand("<sfile>:p:r")."x.vim"
if filereadable(s:sx)
  exe "source " . fnameescape(s:sx)
endif
let &g:so = s:so_save | let &g:siso = s:siso_save
doautoall SessionLoadPost
unlet SessionLoad
" vim: set ft=vim :
