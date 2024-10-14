# nixos-exlinux-kexec-chainbooter

This is mostly relevant for s390x (IBM system Z mainframe)-systems running in the IBM OSS cloud. Since ibm atm doesn't exactly provide me with serial access in the OSS web interface , despite having sponsored my mainframe buildserver ... This script sort of emulates in a sense what I'd hope to see on a serial console, if only i had one :|

Essentially what you do is you install some kernel+initrd including this and kexec onto your bootloader in my case thats a zipl without a serial console but this would pretty much work on any kexec capable system like x86. 

What you then do is you select this script as the default ssh login shell or sth, if this script pops up you can get some sort of menu to select bootloader entries. Very useful for NixOS to select generations if you screwed up your previous one and on an all remote system with no out of bound serial console can no longer fix it/roll back/ mount a rescue image.


### what issue does this solve though?

Well we all like and love nixos-rebuild or your system update/grade/rebuild of choice ... but sometimes things do go wrong. Sometimes you do screw up the firewall, sometimes you did forget the root pw, sometimes this and that.
If you can't really interface with the bootloader / initrd trough the means of an external serial console you better make sure you have some way into the system during its boot that always works even if your primary system
is completely broken. Essentially like an intentional "backdoor" or like LinuxBOOT style kexec bootchain dunno.

While this should work on all extlinux configurations, the primary idea is to use this on NixOS hosts like on the mainframe in the OSS cloud. So what youd have to do for that is roughly

```
boot.loader.generic-extlinux-compatible.enable = true;
```

this then "generates an extlinux-compatible configuration file under /boot/extlinux.conf"

## TODO 

-Add a flake to build it using the dependencies present in the initrd. 
-more testing (shell fallbacks in case of issues or (q) already work)
