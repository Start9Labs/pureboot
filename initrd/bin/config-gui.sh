#!/bin/sh
#
set -e -o pipefail
. /etc/functions
. /etc/gui_functions
. /tmp/config

ROOT_HASH_FILE="/boot/kexec_root_hashes.txt"

param=$1

while true; do
  if [ ! -z "$param" ]; then
    # use first char from parameter
    menu_choice=${param::1}
    unset param
  else
    # check current state of blob jail
    if grep -q 'CONFIG_USE_BLOB_JAIL' /tmp/config; then 
      USE_JAIL=`grep 'CONFIG_USE_BLOB_JAIL=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      [ "$USE_JAIL" == "y" ] && JAIL_ACTION="Disable" || JAIL_ACTION="Enable"
    else
      USE_JAIL=n
      JAIL_ACTION="Enable"
    fi
    # check current Pureboot Mode
    if grep -q 'CONFIG_PUREBOOT_BASIC' /tmp/config; then 
      BASIC_MODE=`grep 'CONFIG_PUREBOOT_BASIC=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      [ "$BASIC_MODE" == "y" ] && MODE_ACTION="Disable" || MODE_ACTION="Enable"
    else
      BASIC_MODE=n
      MODE_ACTION="Enable"
    fi

    unset menu_choice
    whiptail $BG_COLOR_MAIN_MENU --clear --title "Config Management Menu" \
    --menu "This menu lets you change settings for the current BIOS session.\n\nAll changes will revert after a reboot,\n\nunless you also save them to the running BIOS." 20 90 10 \
    'b' ' Change the /boot device' \
    'r' ' Clear GPG key(s) and reset all user settings' \
    'R' ' Change the root device for hashing' \
    'D' ' Change the root directories to hash' \
    'B' ' Check root hashes at boot' \
    'J' " $JAIL_ACTION Firmware Blob Jail" \
    'P' " $MODE_ACTION Pureboot Basic Mode" \
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
      /bin/flash.sh -r /tmp/config-gui.rom
      if [ ! -s /tmp/config-gui.rom ]; then
        whiptail $BG_COLOR_ERROR --title 'ERROR: BIOS Read Failed!' \
          --msgbox "Unable to read BIOS" 16 60
        exit 1
      fi

      if (cbfs -o /tmp/config-gui.rom -l | grep -q "heads/initrd/etc/config.user") then
        cbfs -o /tmp/config-gui.rom -d "heads/initrd/etc/config.user"
      fi
      cbfs -o /tmp/config-gui.rom -a "heads/initrd/etc/config.user" -f /etc/config.user

      if (whiptail --title 'Update ROM?' \
          --yesno "This will reflash your BIOS with the updated version\n\nDo you want to proceed?" 16 90) then
        /bin/flash.sh /tmp/config-gui.rom
        whiptail --title 'BIOS Updated Successfully' \
          --msgbox "BIOS updated successfully.\n\nIf your keys have changed, be sure to re-sign all files in /boot\nafter you reboot.\n\nPress Enter to reboot" 16 60
        /bin/reboot
      else
        exit 0
      fi
    ;;
    "r" )
      # prompt for confirmation
      if (whiptail $BG_COLOR_WARNING --title 'Reset Configuration?' \
           --yesno "This will clear all GPG keys, clear boot signatures and checksums,
                  \nreset the /boot device, clear/reset the TPM (if present),
                  \nand reflash your BIOS with the cleaned configuration.
                  \n\nDo you want to proceed?" 16 90) then
        # read current firmware
        /bin/flash.sh -r /tmp/config-gui.rom
        if [ ! -s /tmp/config-gui.rom ]; then
          whiptail $BG_COLOR_ERROR --title 'ERROR: BIOS Read Failed!' \
            --msgbox "Unable to read BIOS" 16 60
          exit 1
        fi
        # clear local keyring
        rm /.gnupg/* | true
        # clear /boot signatures/checksums
        mount -o remount,rw /boot
        rm /boot/kexec* | true
        mount -o remount,ro /boot
        # clear GPG keys and user settings
        for i in `cbfs -o /tmp/config-gui.rom -l | grep -e "heads/"`; do
          cbfs -o /tmp/config-gui.rom -d $i
        done
        # flash cleared ROM
        /bin/flash.sh -c /tmp/config-gui.rom
        # reset TPM if present
        if [ "$CONFIG_TPM" = "y" ]; then
          /bin/tpm-reset
        fi
        whiptail --title 'Configuration Reset Updated Successfully' \
          --msgbox "Configuration reset and BIOS updated successfully.\n\nPress Enter to reboot" 16 60
        /bin/reboot
      else
        exit 0
      fi
    ;;
    "R" )
      CURRENT_OPTION=`grep 'CONFIG_ROOT_DEV=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      fdisk -l | grep "Disk /dev/" | cut -f2 -d " " | cut -f1 -d ":" > /tmp/disklist.txt
      # filter out extraneous options
      > /tmp/root_device_list.txt
      for i in `cat /tmp/disklist.txt`; do
        # remove block device from list if numeric partitions exist, since not bootable
        DEV_NUM_PARTITIONS=$((`ls -1 $i* | wc -l`-1))
        if [ ${DEV_NUM_PARTITIONS} -eq 0 ]; then
          echo $i >> /tmp/root_device_list.txt
        else
          ls $i* | tail -${DEV_NUM_PARTITIONS} >> /tmp/root_device_list.txt
        fi
      done
      file_selector "/tmp/root_device_list.txt" \
          "Choose the default root device.\n\nCurrently set to $CURRENT_OPTION." \
          "Root Device Selection"
      if [ "$FILE" == "" ]; then
        return
      else
        SELECTED_FILE=$FILE
      fi

      replace_config /etc/config.user "CONFIG_ROOT_DEV" "$SELECTED_FILE"
      combine_configs

      whiptail --title 'Config change successful' \
        --msgbox "The root device was successfully changed to $SELECTED_FILE" 16 60
    ;;
    "D" )
      CURRENT_OPTION=`grep 'CONFIG_ROOT_DIRLIST=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      
      echo "The current list of directories to hash is $CURRENT_OPTION"
      echo -e "\nEnter the new list of directories separated by spaces, without any beginning forward slashes:"
      echo -e "(Press enter with the list empty to cancel)"
      read -r NEW_CONFIG_ROOT_DIRLIST

      # strip any leading forward slashes in case the user ignored us
      NEW_CONFIG_ROOT_DIRLIST=$(echo $NEW_CONFIG_ROOT_DIRLIST | sed -e 's/^\///;s/ \// /g')

      #check if list empty
      if [ -s $NEW_CONFIG_ROOT_DIRLIST ] ; then
        whiptail --title 'Config change canceled' \
        --msgbox "Root device directory change canceled by user" 16 60
        break
      fi

      replace_config /etc/config.user "CONFIG_ROOT_DIRLIST" "$NEW_CONFIG_ROOT_DIRLIST"
      combine_configs

      whiptail --title 'Config change successful' \
        --msgbox "The root directories to hash was successfully changed to:\n$NEW_CONFIG_ROOT_DIRLIST" 16 60
    ;;
    "B" )
      CURRENT_OPTION=`grep 'CONFIG_ROOT_CHECK_AT_BOOT=' /tmp/config | tail -n1 | cut -f2 -d '=' | tr -d '"'`
      if [ "$CURRENT_OPTION" = "n" ]; then
        if (whiptail --title 'Enable Root Hash Check at Boot?' \
             --yesno "This will enable checking root hashes each time you boot.
                    \nDepending on the directories you are checking, this might add
                    \na minute or more to the boot time.
                    \n\nDo you want to proceed?" 16 90) then

          replace_config /etc/config.user "CONFIG_ROOT_CHECK_AT_BOOT" "y"
          combine_configs

          # check that root hash file exists
          if [ ! -f ${ROOT_HASH_FILE} ]; then
            if (whiptail --title 'Generate Root Hash File' \
                --yesno "\nNo root hash file exists.
                        \nWould you like to create the initial hash file now?" 16 90) then
                root-hashes-gui.sh -n
              fi
          fi

          whiptail --title 'Config change successful' \
            --msgbox "The root device will be checked at each boot." 16 60

        fi
      else
        if (whiptail --title 'Disable Root Hash Check at Boot?' \
             --yesno "This will disable checking root hashes each time you boot.
                    \n\nDo you want to proceed?" 16 90) then

          replace_config /etc/config.user "CONFIG_ROOT_CHECK_AT_BOOT" "n"
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "The root device will not be checked at each boot." 16 60
        fi
      fi
    ;;
    "J" )
      if [ "$USE_JAIL" = "n" ]; then
        if (whiptail --title 'Enable Firmware Blob Jail?' \
             --yesno "This will enable loading of firmware from flash on each boot
                    \n\nDo you want to proceed?" 16 90) then

          if grep -q "CONFIG_USE_BLOB_JAIL" /etc/config.user; then
            replace_config /etc/config.user "CONFIG_USE_BLOB_JAIL" "y"
          else
            echo "export CONFIG_USE_BLOB_JAIL=y" >> /etc/config.user
          fi
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Firmware Blob Jail use has been enabled;\nsave the config change and reboot for it to go into effect." 16 60

        fi
      else
        if (whiptail --title 'Disable Firmware Blob Jail?' \
             --yesno "This will disable loading of firmware from flash on each boot.
                    \n\nDo you want to proceed?" 16 90) then
          # remove kernel param
          replace_config /etc/config.user "CONFIG_BOOT_KERNEL_ADD" \
              "${CONFIG_BOOT_KERNEL_ADD//firmware_class.path=\/boot\/firmware\//}"
          if grep -q "CONFIG_USE_BLOB_JAIL" /etc/config.user; then
            replace_config /etc/config.user "CONFIG_USE_BLOB_JAIL" "n"
          else
            echo "export CONFIG_USE_BLOB_JAIL=n" >> /etc/config.user
          fi
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Firmware Blob Jail use has been disabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      fi
    ;;
    "P" )
      if [ "$BASIC_MODE" = "n" ]; then
        if (whiptail --title 'Enable Pureboot Basic Mode?' \
             --yesno "This will remove all signature checking on the firmware
                    \nand boot files, and disable use of the Librem Key.
                    \n\nDo you want to proceed?" 16 90) then

          if grep -q "CONFIG_PUREBOOT_BASIC" /etc/config.user; then
            replace_config /etc/config.user "CONFIG_PUREBOOT_BASIC" "y"
          else
            echo "export CONFIG_PUREBOOT_BASIC=y" >> /etc/config.user
          fi
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Pureboot Basic mode enabled;\nsave the config change and reboot for it to go into effect." 16 60

        fi
      else
        if (whiptail --title 'Disable Pureboot Basic Mode?' \
             --yesno "This will enable all signature checking on the firmware
                    \nand boot files, and enable use of the Librem Key.
                    \n\nDo you want to proceed?" 16 90) then

          if grep -q "CONFIG_PUREBOOT_BASIC" /etc/config.user; then
            replace_config /etc/config.user "CONFIG_PUREBOOT_BASIC" "n"
          else
            echo "export CONFIG_PUREBOOT_BASIC=n" >> /etc/config.user
          fi
          combine_configs

          whiptail --title 'Config change successful' \
            --msgbox "Pureboot Basic mode has been disabled;\nsave the config change and reboot for it to go into effect." 16 60
        fi
      fi
    ;;
  esac

done
exit 0
