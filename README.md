# scripts

---

---

## structure

scripts
├── offensive_tooling
└── productivity_tools
├── contacts-fixer
│   └── src
├── os_builder
│   └── fedora-postinstall
│   └── configs
├── sketch-webapp
├── web-fingerprinter
│   └── app
└── web-scraper
└── src

## overview

these are just some of the scripts that I'm running that are more than just simple functions but not blown out to deserve their own repo. i'll run through a quick description of each one of them

## scripts

### [conditional_sql_injector](https://github.com/AlteredDimension/babyprojects/blob/nexus/offensive_tooling/conditional_sql_injector.py)

i made this for blind sql injection. bruteforcing in burp was taking too long and i was getting throttled - so i wrote some logic that cuts the bruteforce time to a fraction.

### [webtime.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/productivity_tools/webtime.py)

this is my most recent - it just turns virsh and virt viewer into a tui so no need to enter commands, just select the vm you wanna start or stop and click through. i made it for scale so i could expand it to have most of the relevant features. i also might add this to waybar.

### [keepassxc_waybar.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/productivity_tools/keepassxc_waybar.py) (not completed)

this might end up getting its own repo depending on how much i wanna put into this. the cli makes it really nice so you don't have to use the gui. i think it would be really cool to have a tray item that you can click and popout a search bar to get passwords when you're in weird spots that plugins don't cover (like ssh)

#### how it works

### [os_builder](https://github.com/AlteredDimension/babyprojects/tree/nexus/productivity_tools/os_builder) (done)

most of the `.sh` comes from these - it's the scripts i generated from when i migrated over from nixos (btw). since nix is imparative os and arch and fedora are declarative, i thought it'd be nice to have something similar to the nixos config.

### [symlink_looper.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/productivity_tools/symlink_looper.py) (done)

this one is pretty simple, it just moves all the files out of a directory and symlinks them back. not much different than [GNU Snow](https://github.com/aspiers/stow/) or any other symlink farm - but honestly, i just don't have the investment for their tool and the complexities. this is just for gettin it done.

#### how it works

def check the code - it loops through a dir and asks y/n to link. i hardcoded the path that the files would be placed into so def change that variable `dotFilePath`. i'll make it fancy and better if anyone comments or anything.

### [web-fingerprinter](https://github.com/AlteredDimension/babyprojects/tree/nexus/productivity_tools/web-fingerprinter) (done)

this one was cool - unfortunately, my friend was being harassed on the internet so i helped him make a website that looked like a gofundme. it was to bait the offender into clicking it and this pulls IP and a few other things.

### [sketch-webapp](https://github.com/AlteredDimension/babyprojects/blob/nexus/productivity_tools/simple_sketchpad.html) (done)

i have a really old ipad and wanted to put it to use but it couldn't run anything. i made a site i could host so i could draw on it and then just screenshot it when i'm done. just host it with `python -m http.serve <pick a port>`

### [contacts-fixer](https://github.com/AlteredDimension/babyprojects/tree/nexus/productivity_tools/contacts-fixer) (done)

this just sorted through my google contacts list and cleaned up the duplicate numbers. don't worry - you're not gonna see my contacts csv in there ;)
