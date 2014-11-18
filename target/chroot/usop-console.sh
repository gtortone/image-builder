#!/bin/sh -e
#
# Copyright (c) 2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	if [ -f /lib/systemd/system/serial-getty@.service ] ; then
		cp /lib/systemd/system/serial-getty@.service /etc/systemd/system/serial-getty@ttyGS0.service
		ln -s /etc/systemd/system/serial-getty@ttyGS0.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service

		echo "" >> /etc/securetty
		echo "#USB Gadget Serial Port" >> /etc/securetty
		echo "ttyGS0" >> /etc/securetty
	fi
}

install_kernel_modules () {
	dist=${deb_codename}
	arch=${deb_arch}
	mirror="https://rcn-ee.net/deb"
	latest_kernel=$(ls /boot/ | grep vmlinuz | grep bone | head -n 1 | awk -F "vmlinuz-" '{print $2}' || true)

	if [ ! "x${latest_kernel}" = "x" ] ; then

		if [ -f /etc/rcn-ee.conf ] ; then
			. /etc/rcn-ee.conf

			if [ "x${third_party_modules}" = "xenable" ] ; then
				echo "Debug: third_party_modules enabled in /etc/rcn-ee.conf"

				cd /tmp/
				if [ -f /tmp/index.html ] ; then
					rm -f /tmp/index.html || true
				fi

				wget ${mirror}/${dist}-${arch}/v${latest_kernel}/
				unset thirdparty_file
				thirdparty_file=$(cat /tmp/index.html | grep thirdparty | head -n 1)
				thirdparty_file=$(echo ${thirdparty_file} | awk -F "\"" '{print $2}')
				rm -f /tmp/index.html || true

				if [ "x${thirdparty_file}" = "xthirdparty" ] ; then

					if [ -f /tmp/thirdparty ] ; then
						rm -rf /tmp/thirdparty || true
					fi

					wget ${mirror}/${dist}-${arch}/v${latest_kernel}/thirdparty

					if [ -f /tmp/thirdparty ] ; then
						/bin/sh /tmp/thirdparty
						depmod ${latest_kernel} -a
						update-initramfs -uk ${latest_kernel}
						rm -rf /tmp/thirdparty || true
						echo "Debug: third party kernel modules now installed."
					fi

				fi
				cd /
			fi
		fi

	fi
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}

is_this_qemu
setup_system

install_kernel_modules
unsecure_root
#
