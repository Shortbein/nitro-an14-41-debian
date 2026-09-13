# Acer Nitro AN14-41 – ASense support

Tested system:

- Acer Nitro AN14-41
- BIOS V1.06
- Debian 13.7
- Kernel 6.12.107+deb13-amd64
- ASense 0.3.0

## Working

- platform profiles
- 80% battery charge limit
- WMI keyboard RGB
- four physical RGB zones
- static colors
- independent zone colors
- brightness
- RGB state readback
- cold-boot recognition
- RGB autostart

## RGB firmware quirk

The AN14-41 can report a persisted boot-time RGB state that does not pass
the generic ASense effect validator.

Observed states included:

    mode=3
    speed=0
    direction=0
    engine=3

and after a static state had been saved:

    mode=3
    speed=0
    direction=0
    engine=0

The included patch narrowly accepts this condition only for the DMI product:

    Nitro AN14-41

Four physical zones were verified independently.

## Preferred RGB state

- STATIC
- #FFB000
- brightness 30%
- all four zones equal

The systemd oneshot service applies this state after boot.

## Known fan limitations

- automatic mode detected
- manual fan control not available
- no RPM channels exposed
- maximum mode not physically confirmed

No EC register hacks are used.
