#!/bin/sh
#
set -e -o pipefail
. /etc/functions
. /etc/gui_functions
. /tmp/config

ROOT_HASH_FILE="/boot/kexec_root_hashes.txt"

param=$1

# Read the current ROM; if it fails display an error and exit.
read_rom() {
  /bin/flash.sh -r "$1"
  if [ ! -s "$1" ]; then
    whiptail $BG_COLOR_ERROR --title 'ERROR: BIOS Read Failed!' \
      --msgbox "Unable to read BIOS" 16 60
    exit 1
  fi
}

while true; do
  if [ ! -z "$param" ]; then
    # use first char from parameter
    menu_choice=${param::1}
    unset param
  else
    # check current PureBoot Mode
    BASIC_MODE="$(load_config_value CONFIG_PUREBOOT_BASIC)"
    BASIC_NO_AUTOMATIC_DEFAULT="$(load_config_value CONFIG_BASIC_NO_AUTOMATIC_DEFAULT)"
    BASIC_USB_AUTOBOOT="$(load_config_value CONFIG_BASIC_USB_AUTOBOOT)"

    unset menu_choice
    whiptail $BG_COLOR_MAIN_MENU --clear --title "Config Management Menu" \
    --menu "This menu lets you change settings for the current BIOS session.\n\nAll changes will revert after a reboot,\n\nunless you also save them to the running BIOS." 0 80 10 \
    'b' ' Change the /boot device' \
    'P' " $(get_config_display_action "$BASIC_MODE") PureBoot Basic Mode" \
    'A' " $(get_inverted_config_display_action "$BASIC_NO_AUTOMATIC_DEFAULT") automatic default boot" \
    'U' " $(get_config_display_action "$BASIC_USB_AUTOBOOT") USB automatic boot" \
    's' ' Save the current configuration to the running BIOS' \
    'x' ' Return to Main Menu' \
    2>/tmp/whiptail || recovery "GUI menu failed"

    menu_choice=$(cat /tmp/whiptail)
  fi

  case "$menu_choice" in
    "x" )
      exit 0
    ;;
    "b" )
      CURRENT_OPTION=`grep 'CONFIG_BOOT_DEV=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      if ! fdisk -l | grep "Disk /dev/" | cut -f2 -d " " | cut -f1 -d ":" > /tmp/disklist.txt ; then
        whiptail $BG_COLOR_ERROR --title 'ERROR: No bootable devices found' \
          --msgbox "    $ERROR\n\n" 16 60
        exit 1
      fi
      # filter out extraneous options
      > /tmp/boot_device_list.txt
      for i in `cat /tmp/disklist.txt`; do
        # remove block device from list if numeric partitions exist, since not bootable
        DEV_NUM_PARTITIONS=$((`ls -1 $i* | wc -l`-1))
        if [ ${DEV_NUM_PARTITIONS} -eq 0 ]; then
          echo $i >> /tmp/boot_device_list.txt
        else
          ls $i* | tail -${DEV_NUM_PARTITIONS} >> /tmp/boot_device_list.txt
        fi
      done
      file_selector "/tmp/boot_device_list.txt" \
          "Choose the default /boot device.\n\nCurrently set to $CURRENT_OPTION." \
          "Boot Device Selection"
      if [ "$FILE" == "" ]; then
        return
      else
        SELECTED_FILE=$FILE
      fi

      # unmount /boot if needed
      if grep -q /boot /proc/mounts ; then
        umount /boot 2>/dev/null
      fi
      # mount newly selected /boot device
      if ! mount -o ro $SELECTED_FILE /boot 2>/tmp/error ; then
        ERROR=`cat /tmp/error`
        whiptail $BG_COLOR_ERROR --title 'ERROR: unable to mount /boot' \
          --msgbox "    $ERROR\n\n" 16 60
        exit 1
      fi

      replace_config /etc/config.user "CONFIG_BOOT_DEV" "$SELECTED_FILE"
      combine_configs

      whiptail --title 'Config change successful' \
        --msgbox "The /boot device was successfully changed to $SELECTED_FILE" 16 60
    ;;
    "s" )
      read_rom /tmp/config-gui.rom

      replace_rom_file /tmp/config-gui.rom "heads/initrd/etc/config.user" /etc/config.user

      if (whiptail --title 'Update ROM?' \
          --yesno "This will reflash your BIOS with the updated version\n\nDo you want to proceed?" 0 80) then
        /bin/flash.sh /tmp/config-gui.rom
        whiptail --title 'BIOS Updated Successfully' \
          --msgbox "BIOS updated successfully.\n\nIf your keys have changed, be sure to re-sign all files in /boot\nafter you reboot.\n\nPress Enter to reboot" 16 60
        /bin/reboot
      else
        exit 0
      fi
    ;;
    "P" )
      if [ "$BASIC_MODE" = "n" ]; then
        if (whiptail --title 'Enable PureBoot Basic Mode?' \
             --yesno "This will remove all signature checking on the firmware
                    \nand boot files, and disable use of the Librem Key.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_PUREBOOT_BASIC" "y"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "PureBoot Basic mode enabled;\nsave the config change and reboot for it to go into effect." 16 60

        fi
      else
        if (whiptail --title 'Disable PureBoot Basic Mode?' \
             --yesno "This will enable all signature checking on the firmware
                    \nand boot files, and enable use of the Librem Key.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_PUREBOOT_BASIC" "n"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "PureBoot Basic mode has been disabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      fi
    ;;
    "A" )
      if [ "$BASIC_NO_AUTOMATIC_DEFAULT" = "n" ]; then
        if (whiptail --title 'Disable automatic default boot?' \
             --yesno "You will need to select a default boot option.
                    \nIf the boot options are changed, such as for an OS update,
                    \nyou will be prompted to select a new default.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_BASIC_NO_AUTOMATIC_DEFAULT" "y"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Automatic default boot disabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      else
        if (whiptail --title 'Enable automatic default boot?' \
             --yesno "The first boot option will be used automatically.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_BASIC_NO_AUTOMATIC_DEFAULT" "n"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Automatic default boot enabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      fi
    ;;
    "U" )
      if [ "$BASIC_USB_AUTOBOOT" = "n" ]; then
        if (whiptail --title 'Enable USB automatic boot?' \
             --yesno "During boot, an attached bootable USB disk will be booted 
                    \nby default instead of the installed operating system.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_BASIC_USB_AUTOBOOT" "y"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "USB automatic boot enabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      else
        if (whiptail --title 'Disable USB automatic boot?' \
             --yesno "USB disks will no longer be booted by default.
                    \n\nDo you want to proceed?" 0 80) then

          set_config /etc/config.user "CONFIG_BASIC_USB_AUTOBOOT" "n"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "USB automatic boot disabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      fi
    ;;
  esac

done
exit 0
