#!/usr/bin/env bash

Upgrade_Multiplephp()
{
    Echo_Yellow "Multiple-PHP upgrades use the same supported installer and preserve a versioned prefix."
    Echo_Yellow "Select the target branch; its existing prefix is updated in place after configuration backup."
    Install_Multiplephp
}
