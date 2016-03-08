#!/usr/bin/bash

# openhab service user
OPENHAB_USER=openhab
SU_USER=admin

create_openhab_user() {

	echo "Create openhab user"
	
	#groupadd $GROUP
	
	useradd -U -s /usr/bin/nologin $OPENHAB_USER

	# Access group for >> Serial and USB devices such as modems, handhelds, RS-232/serial ports.
	gpasswd -a $OPENHAB_USER uucp

	# Access group for >> Eg. to acces /dev/ACMx
	gpasswd -a $OPENHAB_USER tty

	# Access group for >> Access the lock directory
	gpasswd -a $OPENHAB_USER lock

	# Access group for >> daemon ?
	gpasswd -a $OPENHAB_USER daemon

}

create_su_user() {

	echo "Create admin"

	useradd -m -U -s /bin/bash $SU_USER

	# Access group for >> sudo root
	gpasswd -a $SU_USER wheel

	passwd admin
}

install_acpi() {

	echo "Install ACPI service"

	# install ACPI
	pacman -S acpid --noconfirm

	cat << __EOF__ >> /etc/acpi/events/power-button
event=button power.*
action=/etc/acpi/actions/power-button.sh %e
__EOF__

	cat << __EOF__ >> /etc/acpi/actions/power-button.sh
#!/bin/sh
systemctl poweroff
__EOF__

	chmod 755 /etc/acpi/actions/power-button.sh

	# enable ACPI service
	systemctl enable acpid.service

	# start ACPI service
	systemctl start acpid
}

install_yaourt() {

	echo "Install yaourt"
	su $SU_USER
	
	pacman -S base-devel --noconfirm

	curl -O https://aur.archlinux.org/cgit/aur.git/snapshot/package-query.tar.gz
	tar -xvzf package-query.tar.gz
	cd package-query
	makepkg -si

	cd ..
	curl -O https://aur.archlinux.org/cgit/aur.git/snapshot/yaourt.tar.gz
	tar -xvzf yaourt.tar.gz
	cd yaourt

	exit
}

initial_system() {

	echo "Init system"

	#grep -E -A 1 ".*Germany.*$" /etc/pacman.d/mirrorlist.bak | sed '/--/d' > /etc/pacman.d/mirrorlist

	# set hostname
	echo "Set hostname"
	echo openhab2 > root/etc/hostname

	# set locals
	echo "Set locals"
	echo LANG=de_DE.UTF-8 > root/etc/locale.conf
	echo KEYMAP=de-latin1 > root/etc/vconsole.conf
	ln -s /usr/share/zoneinfo/Europe/Berlin root/etc/localtime
	echo 'de_DE.UTF-8 UTF-8' > root/etc/locale.gen

	# Update locals
	locale-gen

	# Refresh system
	pacman -Syu --noconfirm

	#enable wheel group for sudo
	sed --in-place 's/^#\s*\(%wheel\s*ALL=(ALL)\s*NOPASSWD:\s*ALL\)/\1/' /etc/sudoers
	#sed --in-place 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+NOPASSWD:\s\+ALL\)/\1/' /etc/sudoers
}

install_docker() {

	echo "Install docker"

	# Docker part
	pacman -S docker --noconfirm
	systemctl enable docker
	systemctl start docker

}

disable_root() {

	echo "Disable root account"

	passwd -l root
}

enable_root() {
	echo "Enable root account"
	sudo passwd -u root
}

prepare_udev() {

	echo "Set UDEV"

	# Add reliable serial ftdi device links
	cat << __EOF__ >> /etc/udev/rules.d/52-openhab-ftdi.rules
SUBSYSTEMS=="usb", KERNEL=="ttyUSB[0-9]*", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="ttyFTDI_%s{serial}"
__EOF__

	# Allow access to usb like HID devices
	cat << __EOF__ >> /etc/udev/rules.d/53-openhab-usb.rules
SUBSYSTEM=="usb", GROUP="${GROUP}", MODE="0660"
__EOF__

	# reload trigger
	udevadm trigger

}

prepare_lock() {

		echo "Repare lock"

	# Allow access to usb like HID devices
	cat << __EOF__ >> /etc/tmpfiles.d/legacy.conf
# /etc/tmpfiles.d/legacy.conf
# Type Path Mode UID GID Age Argument
d /var/lock 0775 root lock - -
d /var/lock/lockdev 0775 root lock - -
__EOF__

}


expand_root_partition() {

	echo "Resize root partition"

	# Install parted to update root partition
	pacman -S parted --noconfirm

	p1_start=`fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $2}'`
	echo "Found the start point of mmcblk0p1: $p1_start"
	fdisk /dev/mmcblk0 << __EOF__ >> /dev/null
d
1
n
p
1
$p1_start

p
w
__EOF__

	sync

	# refresh partition table
	partprobe /dev/mmcblk0

	echo "Activating the new size"
	resize2fs /dev/mmcblk0p1 >> /dev/null
	echo "Done!"
	echo "Enjoy your new space!"
	rm -rf /root/.resize

	echo "Ok, Partition resized, please reboot now"
	echo "Once the reboot is completed please run this script again"
}

case $1 in
  initial) initial_system ;;
  expand_root_partition) expand_root_partition;;
  prepare_udev) prepare_udev;;
  prepare_lock) prepare_lock;;
  create_openhab_user) create_openhab_user;;
  install_docker) install_docker;;
  install_yaourt) install_yaourt;;
  create_user2) create_user2;;
  install_acpi) install_acpi;;
  
  *) 	initial_system
		prepare_udev
		prepare_lock
		create_openhab_user
		create_su_user
		install_acpi
		expand_root_partition
		;;
esac
