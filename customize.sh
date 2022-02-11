##########################################################################################
#
# MMT Extended Config Script
#
##########################################################################################

##########################################################################################
# Config Flags
##########################################################################################

# Uncomment and change 'MINAPI' and 'MAXAPI' to the minimum and maximum android version for your mod
# Uncomment DYNLIB if you want libs installed to vendor for oreo+ and system for anything older
# Uncomment DEBUG if you want full debug logs (saved to /sdcard)
#MINAPI=21
#MAXAPI=25
#DYNLIB=true
#DEBUG=true

##########################################################################################
# Replace list
##########################################################################################

# List all directories you want to directly replace in the system
# Check the documentations for more info why you would need this

# Construct your list in the following format
# This is an example
REPLACE_EXAMPLE="
/system/app/Youtube
/system/priv-app/SystemUI
/system/priv-app/Settings
/system/framework
"

# Construct your own list here
REPLACE="
"

on_install() {

ui_print "- Extracting module files"
  unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2
  unzip -oj "$ZIPFILE" 'init.custom.rc' 'init.vold.rc' -d $MODPATH >&2
 
patch_boot

}


  

##########################################################################################
# Permissions
##########################################################################################

set_permissions() {
  : # Remove this if adding to this function

  # Note that all files/folders in magisk module directory have the $MODPATH prefix - keep this prefix on all of your files/folders
  # Some examples:
  
  # For directories (includes files in them):
  # set_perm_recursive  <dirname>                <owner> <group> <dirpermission> <filepermission> <contexts> (default: u:object_r:system_file:s0)
  
  # set_perm_recursive $MODPATH/system/lib 0 0 0755 0644
  # set_perm_recursive $MODPATH/system/vendor/lib/soundfx 0 0 0755 0644

  # For files (not in directories taken care of above)
  # set_perm  <filename>                         <owner> <group> <permission> <contexts> (default: u:object_r:system_file:s0)
  
  # set_perm $MODPATH/system/lib/libart.so 0 0 0644
  # set_perm /data/local/tmp/file.txt 0 0 644
  
  
  set_perm_recursive $MODPATH/system  0  0  0755  0644
  set_perm_recursive $MODPATH/system/bin  0  2000  0755  0755
  set_perm  $MODPATH/magiskinit  0  0  0755
  set_perm  $MODPATH/system/bin/vold  0  2000  0755  u:object_r:vold_exec:s0
  set_perm  $MODPATH/system/bin/fsck.exfat  0  2000  0755  u:object_r:fsck_exec:s0
  #set_perm  $MODPATH/system/bin/fsck.ntfs  0  2000  0755  u:object_r:fsck_exec:s0
}

patch_boot() {
  get_flags
  find_boot_image
  find_manager_apk

  eval $BOOTSIGNER -verify < $BOOTIMAGE && BOOTSIGNED=true
  $BOOTSIGNED && ui_print "- Boot image is signed with AVB 1.0"

  [ -z $BOOTIMAGE ] && abort "! Unable to detect target image"
  ui_print "- Target image: $BOOTIMAGE"
  [ -e "$BOOTIMAGE" ] || abort "$BOOTIMAGE does not exist!"

  ui_print "- Unpacking boot image"
  /data/adb/magisk/magiskboot --unpack "$BOOTIMAGE"

  case $? in
    1 )
      abort "! Unable to unpack boot image"
      ;;
    2 )
      ui_print "- ChromeOS boot image detected"
      abort "! Unsupport type"
      ;;
    3 )
      ui_print "! Sony ELF32 format detected"
      abort "! Unsupport type"
      ;;
    4 )
      ui_print "! Sony ELF64 format detected"
      abort "! Unsupport type"
  esac

  ui_print "- Checking ramdisk status"
  if [ -e ramdisk.cpio ]; then
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio test
    STATUS=$?
  else
    # Stock A only system-as-root
    STATUS=0
  fi
  case $((STATUS & 3)) in
    0 )  # Stock boot
      ui_print "- Stock boot image detected"
      abort "! Please install Magisk first"
      ;;
    1 )  # Magisk patched
      ui_print "- Magisk patched boot image detected"
      ;;
    2 ) # Other patched
      ui_print "! Boot image patched by unsupported programs"
      abort "! Please restore stock boot image"
      ;;
  esac

  if [ $((STATUS & 8)) -ne 0 ]; then
    # Possibly using 2SI, export env var
    export TWOSTAGEINIT=true
  fi

  ui_print "- Patching ramdisk"

    /data/adb/magisk/magiskboot --cpio ramdisk.cpio \
    "mkdir 755 overlay.d" \
    "mkdir 755 overlay.d/sbin" \
    "add 755 overlay.d/sbin/vold $MODPATH/system/bin/vold" \
    "add 750 overlay.d/init.vold.rc $MODPATH/init.vold.rc" 2>&1
    
   if [ $((STATUS & 4)) -ne 0 ]; then
    ui_print "- Compressing ramdisk"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
  fi

  ui_print "- Repacking boot image"
  /data/adb/magisk/magiskboot --repack "$BOOTIMAGE" || abort "! Unable to repack boot image!"

  ui_print "- Flashing new boot image"
  if ! flash_image new-boot.img "$BOOTIMAGE"; then
    ui_print "- Compressing ramdisk to fit in partition"
    /data/adb/magisk/magiskboot --cpio ramdisk.cpio compress
    /data/adb/magisk/magiskboot --repack "$BOOTIMAGE"
    flash_image new-boot.img "$BOOTIMAGE" || abort "! Insufficient partition size"
  fi
  /data/adb/magisk/magiskboot --cleanup
  rm -f new-boot.img
}  

##########################################################################################
# MMT Extended Logic - Don't modify anything after this
##########################################################################################

SKIPUNZIP=1
unzip -qjo "$ZIPFILE" 'common/functions.sh' -d $TMPDIR >&2
. $TMPDIR/functions.sh
