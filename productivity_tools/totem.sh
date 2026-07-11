#!/run/current-system/sw/bin/zsh
echo "prepare your keyboard"
echo -n "enter boot ... ready (y/n) "
read ANSWER
lsblk
echo -n "which device is left kb? "
read LEFT_KB
sudo mount  -o uid=100,gid=100 /dev/$LEFT_KB /home/alt/mnt
echo "adding settings file"
sudo cp Downloads/totem/settings_reset-xiao_ble__zmk-zmk.uf2 /home/alt/mnt
echo -n "done ... plug in right kb ... ready? "
read ANSWER
lsblk
echo -n "which device is right kb? "
read RIGHT_KB
echo "running mount process ..."
sudo umount  /home/alt/mnt
sudo mount  -o uid=100,gid=100 /dev/$RIGHT_KB /home/alt/mnt
echo "adding settings file"
sudo cp Downloads/totem/settings_reset-xiao_ble__zmk-zmk.uf2 /home/alt/mnt
echo -n "done ... plug in left kb ... ready? "
read ANSWER
sudo umount  /home/alt/mnt
sudo mount  -o uid=100,gid=100 /dev/$LEFT_KB /home/alt/mnt
echo "adding config file"
sudo cp Downloads/totem/totem_left-xiao_ble__zmk-zmk.uf2 /home/alt/mnt
echo -n "done ... plug in right kb ... ready? "
read ANSWER
sudo umount  /home/alt/mnt
sudo mount  -o uid=100,gid=100 /dev/$RIGHT_KB /home/alt/mnt
echo "adding config file"
sudo cp Downloads/totem/totem_right-xiao_ble__zmk-zmk.uf2 /home/alt/mnt 
sudo umount  /home/alt/mnt
echo "done! unplug, turn off then on, reset bluetooth, and connect"
