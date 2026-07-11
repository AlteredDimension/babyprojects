# baby projects

---

---

## overview

these are just some of the scripts that I'm running that are more than just simple functions but not blown out to deserve their own repo. i'll run through a quick description of each one of them

## scripts

### [webtime.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/webtime.py) (done)

this is my most recent - it just turns virsh and virt viewer into a tui so no need to enter commands, just select the vm you wanna start or stop and click through. i made it for scale so i could expand it to have most of the relevant features. i also might add this to waybar.

### [keepassxc_waybar.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/keepassxc_waybar.py) (not completed)

this might end up getting its own repo depending on how much i wanna put into this. the cli makes it really nice so you don't have to use the gui. i think it would be really cool to have a tray item that you can click and popout a search bar to get passwords when you're in weird spots that plugins don't cover (like ssh)

#### how it works

### [os_builder](https://github.com/AlteredDimension/babyprojects/tree/nexus/os_builder) (done)

most of the `.sh` comes from these - it's the scripts i generated from when i migrated over from nixos (btw). since nix is imparative os and arch and fedora are declarative, i thought it'd be nice to have something similar to the nixos config.

### [symlink_looper.py](https://github.com/AlteredDimension/babyprojects/blob/nexus/symlink_looper.py) (done)

this one is pretty simple, it just moves all the files out of a directory and symlinks them back. not much different than [GNU Snow](https://github.com/aspiers/stow/) or any other symlink farm - but honestly, i just don't have the investment for their tool and the complexities. this is just for gettin it done.

#### how it works

def check the code - it loops through a dir and asks y/n to link. i hardcoded the path that the files would be placed into so def change that variable `dotFilePath`. i'll make it fancy and better if anyone comments or anything.

### [web-scraper](https://github.com/AlteredDimension/babyprojects/blob/nexus/web-scraper/src/main.rs) (done)

very specific web scraper. it takes the schedule of basketball games from a website and cleans them down so that i could add them to my google calendar with an upload. saved loads of time.

### [title.txt](https://github.com/AlteredDimension/babyprojects/blob/nexus/title.txt) (done)

honestly this shouldn't even be in here but i figured it fits lol - might just drop it in the README just cause.

### [totem.sh](https://github.com/AlteredDimension/babyprojects/blob/nexus/totem.sh) (pending)

i have a totem keyboard (btw) it has a process for flashing tho so this was meant to automate it. truly can't remember if i got it up and running but i remember it's dang close.

### [web-fingerprinter](https://github.com/AlteredDimension/babyprojects/blob/nexus/web-fingerprinter/index.html) (done)

this one was cool - unfortunately, my friend was being harassed on the internet so i helped him make a website that looked like a gofundme. it was to bait the offender into clicking it and this pulls IP and a few other things.

### [tempurature_converter](https://github.com/AlteredDimension/babyprojects/tree/nexus/temperature_converter) (done)

this was just me learning rust tbh. prob will delete later.

### [sketch-webapp](https://github.com/AlteredDimension/babyprojects/tree/nexus/sketch-webapp) (done)

i have a really old ipad and wanted to put it to use but it couldn't run anything. i made a site i could host so i could draw on it and then just screenshot it when i'm done. just host it with `python -m http.serve <pick a port>`

### [contacts-fixer](https://github.com/AlteredDimension/babyprojects/tree/nexus/contacts-fixer) (done)

this just sorted through my google contacts list and cleaned up the duplicate numbers. don't worry - you're not gonna see my contacts csv in there ;)
