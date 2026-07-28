lsblk 
echo "what number is the nvme"
read NUMBER
cryptsetup open /dev/sda1 CryptLVM_Data
cryptsetup open /dev/nvme${NUMBER}n1p2 CryptLVM_Main
sudo mount --mkdir /dev/vg0/root /mnt
sudo mount --mkdir /dev/vg0/home /mnt/home
sudo mount --mkdir /dev/nvme1n1p1 /mnt/boot
sudo mount --mkdir /dev/vg1/lv_data /mnt/mnt/data
sudo swapon /dev/vg0/swap
lsblk
history
