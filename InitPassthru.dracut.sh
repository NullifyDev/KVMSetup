#! /bin/bash

if [ "$EUID" -ne 0 ]; then
	echo "Please run this script as root"
	echo "Try 'sudo ./SetupPassthrough.sh'"
  	exit
fi

if [[ $1 == "--clear" ]]; then
	clear
fi

echo "WARNING: BY THE END OF THIS SCRIPT, YOUR GPU WILL BE HIJACKED UPON THE NEXT BOOT - IT WILL ONLY BE USABLE BY VFIO-KERNEL AND WILL NOT BE USABLE BY THE HOST!"
echo "MAKE SURE YOU HAVE A SEPARATE GPU INSTALLED ON THE SAME SYSTEM FOR THE HOST BE IT iGPU, dGPU OR eGPU. OTHERWISE, YOU WILL NOT SEE ANYTHING ON YOUR SCREEN"
echo ""
echo "unless you have (or have found) a way to otherwise have your cpu to render the graphical session at a software level, DO NOT CONTINUE WITH THIS SCRIPT"
echo ""
echo ""
echo "USER DISCRETION IS EXPLICITLY ADVISED!"
echo ""
read -p "Press any key to continue."

IommuEnabled=$(dmesg | grep -i -e -DMAR -e IOMMU | grep "IOMMU enabled")
if [[ "$(ls /sys/class/iommu/)" != "" ]]; then
	echo "IOMMU is currently Enabled!"
else
	echo "IOMMU is currently Disabled!"
	echo
	read -p "Making sure all necessary tools are installed"
	pacman -Syu qemu-desktop libvirt ovmf virt-manager ebtables iptables dnsmasq
	echo ""
	echo ""
    echo ""
	systemctl enable libvirtd.service virtlogd.socket --now
	virsh net-start default

	systemctl restart libvirtd
	virsh net-start default
	virsh net-autostart default

	cp /etc/default/grub ./grub/grub.bak.cfg
	clear
	echo "Detecting CPU Vendor and Enabling IOMMU..."
	CpuVendor=$(lscpu | grep "Vendor ID:")

	if [[ $CpuVendor == *"AuthenticAMD"* ]]; then
		echo "AMD Detected!"
		sed -i -e "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='amd_iommu=on iommu=pt /g" /etc/default/grub

	elif [[ $CpuVendor == *"GenuineIntel"* ]]; then
		echo "Intel Detected!"
		sed -i -e "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='intel_iommu=on iommu=pt /g" /etc/default/grub
	else
		echo -e "\033[31;1;1m!!! UNKNOWN VENDOR FOUND!!!\033[0m"
		echo "Please do the manual grub configuration in /etc/grub/grub.cfg for the variable: \"GRUB_CMDLINE_LINUX_DEFAULT\""
		read -p "Then press any key to continue or hit Ctrl+C to cancel"
	fi

	read -p "Provide the path for the grub.cfg file. (Default: \"/boot/grub/grub.cfg\"): " GrubCfgPath
	echo "Configuring Grub..."
	GrubCfgPath=${GrubCfgPath:-/boot/grub/grub.cfg}
	grub-mkconfig -o $GrubCfgPath
	echo ""
	echo ""
	read -p "Reboot? [Y/n]" promptReboot
	if [ $promptReboot == "" ] || [ $(echo "$promptReboot" | perl -ne 'print lc') == "y" ]; then reboot;
	else exit 0
	fi
fi

# CHECK FOR IOMMU GROUPS
shopt -s nullglob
for g in $(find /sys/kernel/iommu_groups/* -maxdepth 0 -type d | sort -V); do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;

echo ""
echo ""
echo ""
echo "\033[31;1;1mPLEASE READ THE FOLLOWING MESSAGE:\033[0m"
echo ""
echo "Please find your desired Graphical Processing Unit (GPU) and note its Device ID by this format: [####:####]"
echo "If your distro doesnt use dracut to rebuild the initramfs, please look up the documentation of the current initramfs compiler of your linux system"
echo "('#' is either number or letter. ':' included without '[' nor ']')"
echo "NOTE: YOU MUST COPY ALL IDs THAT EXIST OR IS PART OF THE SAME GROUP AS SAID DESIRED GPU!"
echo ""
echo "Please type in the Device IDs collected in the format of this example: 1A2B:3C4D"
read -p  "Device ID's here: " DeviceIDs


echo "options vfio-pci ids=$DeviceIDs" > /etc/modprobe.d/vfio.conf
echo "Writing Completed"

echo "force_drivers+=\" vfio_pci vfio vfio_iommu_type1 \"" > /etc/dracut.conf.d/kvm.conf
echo "dracut.conf.d/kvm.conf alteration complete!"

clear
echo ""
read -p "rebuild with dracut (dracut-rebuild)? [Y/n]" promptReboot

if [ $promptReboot == "" ] || [ $(echo "$promptReboot" | perl -ne 'print lc') == "y" ]; then dracut-rebuild;
else exit 0
fi
