# GameMode configuration

Tested on Acer Nitro AN14-41 with Debian 13.7 and amd_pstate=active.

Normal state:

    power profile: balanced
    governor: powersave
    EPP: balance_performance

During GameMode:

    power profile: performance
    governor: performance
    EPP: performance

After GameMode exits, the previous profile is restored.

The custom scripts use powerprofilesctl to switch the platform profile.
GameMode itself uses:

    desiredgov=performance

This combination has been validated with:

    gamemoded -t

Result:

    All Tests Passed!
