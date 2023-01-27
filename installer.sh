#!/bin/bash -p

# EMBA - EMBEDDED LINUX ANALYZER
#
# Copyright 2020-2023 Siemens AG
# Copyright 2020-2023 Siemens Energy AG
#
# EMBA comes with ABSOLUTELY NO WARRANTY. This is free software, and you are
# welcome to redistribute it under the terms of the GNU General Public License.
# See LICENSE file for usage of this software.
#
# EMBA is licensed under GPLv3
#
# Author(s): Michael Messner, Pascal Eckmann
# Contributor(s): Stefan Haboeck, Nikolas Papaioannou

# Description:  Installs needed stuff for EMBA

# it the installer fails you can try to change it to 0
STRICT_MODE=1

ORIG_USER="${SUDO_USER:-${USER}}"
ORIG_GROUP=$(groups "$ORIG_USER" | cut -d: -f2 | awk '{print $1}')

export DEBIAN_FRONTEND=noninteractive
export INSTALL_APP_LIST=()
export DOWNLOAD_FILE_LIST=()
export INSTALLER_DIR="./installer"

if [[ "$STRICT_MODE" -eq 1 ]]; then
  if [[ -f "./helpers/helpers_emba_load_strict_settings.sh" ]]; then
    # shellcheck source=/dev/null
    source ./helpers/helpers_emba_load_strict_settings.sh
  elif [[ -f "/installer/helpers_emba_load_strict_settings.sh" ]]; then
    # in docker this is in /emba/...
    # shellcheck source=/dev/null
    source /installer/helpers_emba_load_strict_settings.sh
  else
    echo "Warning - strict mode module not found"
  fi
  load_strict_mode_settings
  trap 'wickStrictModeFail $? | tee -a /tmp/emba_installer.log' ERR  # The ERR trap is triggered when a script catches an error
fi

# install docker EMBA
export IN_DOCKER=0
# list dependencies
export LIST_DEP=0
export FULL=0
export REMOVE=0
# other os stuff
export OTHER_OS=0
export UBUNTU_OS=0
export WSL=0

## Color definition
export RED="\033[0;31m"
export GREEN="\033[0;32m"
export ORANGE="\033[0;33m"
export MAGENTA="\033[0;35m"
export CYAN="\033[0;36m"
export BLUE="\033[0;34m"
export NC="\033[0m"  # no color

## Attribute definition
export BOLD="\033[1m"

echo -e "\\n""$ORANGE""$BOLD""EMBA - Embedded Linux Analyzer Installer""$NC"
echo -e "$BOLD""=================================================================""$NC"

# import all the installation modules
mapfile -t INSTALLERS < <(find "$INSTALLER_DIR" -iname "*.sh" 2> /dev/null)
INSTALLER_COUNT=0
for INSTALLER_FILE in "${INSTALLERS[@]}" ; do
  # https://github.com/koalaman/shellcheck/wiki/SC1090
  # shellcheck source=/dev/null
  source "$INSTALLER_FILE"
  (( INSTALLER_COUNT+=1 ))
done

echo ""
echo -e "==> ""$GREEN""Imported ""$INSTALLER_COUNT"" installer module files""$NC"
echo ""

if [ "$#" -ne 1 ]; then
  echo -e "$RED""$BOLD""Invalid number of arguments""$NC"
  echo -e "\n\n------------------------------------------------------------------"
  echo -e "Probably you would check all packets we are going to install with:"
  echo -e "$CYAN""     sudo ./installer.sh -l""$NC"
  echo -e "If you are going to install EMBA in default mode you can use:"
  echo -e "$CYAN""     sudo ./installer.sh -d""$NC"
  echo -e "------------------------------------------------------------------\n\n"
  print_help
  exit 1
fi

while getopts cCdDFhlr OPT ; do
  case $OPT in
    d)
      export DOCKER_SETUP=1
      export CVE_SEARCH=0
      echo -e "$GREEN""$BOLD""Install all dependecies for EMBA in default/docker mode""$NC"
      ;;
    D)
      export IN_DOCKER=1
      export DOCKER_SETUP=0
      export CVE_SEARCH=0
      echo -e "$GREEN""$BOLD""Install EMBA in docker image - used for building a docker image""$NC"
      ;;
    F)
      export FULL=1
      export DOCKER_SETUP=0
      export CVE_SEARCH=1
      echo -e "$GREEN""$BOLD""Install all dependecies for developer mode""$NC"
      ;;
    h)
      print_help
      exit 0
      ;;
    l)
      export LIST_DEP=1
      export CVE_SEARCH=0
      export DOCKER_SETUP=0
      echo -e "$GREEN""$BOLD""List all dependecies""$NC"
      ;;
    r)
      export REMOVE=1
      echo -e "$GREEN""$BOLD""Remove EMBA from the system""$NC"
      ;;
    *)
      echo -e "$RED""$BOLD""Invalid option""$NC"
      print_help
      exit 1
      ;;
  esac
done

# WSL support - currently experimental!
if grep -q -i wsl /proc/version; then
  echo -e "\n${ORANGE}INFO: System running in WSL environment!$NC"
  echo -e "\n${ORANGE}INFO: WSL is currently experimental!$NC"
  echo -e "\n${ORANGE}WARNING: If you are using WSL2, disable docker integration from the docker-desktop daemon!$NC"
  read -p "If you know what you are doing you can press any key to continue ..." -n1 -s -r
  WSL=1
fi

# distribution check
if ! grep -q "ID_LIKE=" /etc/os-release | grep -q "ubuntu\|debian" /etc/os-release 2>/dev/null ; then
  echo -e "\\n""$RED""EMBA only supports debian based distributions!""$NC\\n"
  print_help
  exit 1
elif ! grep -q "kali" /etc/debian_version 2>/dev/null ; then
  if grep -q "VERSION_ID=\"22.04\"" /etc/os-release 2>/dev/null ; then 
  # How to handle sub-versioning ? if grep -q -E "PRETTY_NAME=\"Ubuntu\ 22\.04(\.[0-9]+)?\ LTS\"" /etc/os-release 2>/dev/null ; then
    OTHER_OS=1
    UBUNTU_OS=1
  elif grep -q "PRETTY_NAME=\"Ubuntu 20.04 LTS\"" /etc/os-release 2>/dev/null ; then
    echo -e "\\n""$RED""EMBA is not fully supported on Ubuntu 20.04 LTS.""$NC"
    echo -e "$RED""For EMBA installation you need to update docker-compose manually. See also https://github.com/e-m-b-a/emba/issues/247""$NC"
    read -p "If you have updated docker-compose you can press any key to continue ..." -n1 -s -r
    OTHER_OS=0  # installation procedure identical to kali install
    UBUNTU_OS=0 # installation procedure identical to kali install
  else
    echo -e "\n${ORANGE}WARNING: compatibility of distribution/version unknown!$NC"
    OTHER_OS=1
    read -p "If you know what you are doing you can press any key to continue ..." -n1 -s -r
  fi
else
  OTHER_OS=0
  UBUNTU_OS=0
fi

if ! [[ $EUID -eq 0 ]] && [[ $LIST_DEP -eq 0 ]] ; then
  echo -e "\\n""$RED""Run EMBA installation script with root permissions!""$NC\\n"
  print_help
  exit 1
fi

# standard stuff before installation run

HOME_PATH=$(pwd)

if [[ "$REMOVE" -eq 1 ]]; then
  R00_emba_remove
  exit 0
fi

# quick check if we have enough disk space for the docker image

if [[ "$IN_DOCKER" -eq 0 ]]; then
  if [[ -d "/var/lib/docker/" ]]; then
    # docker is already installed
    DDISK="/var/lib/docker"
  else
    # default
    DDISK="/var/lib/"
  fi

  FREE_SPACE=$(df --output=avail "$DDISK" | awk 'NR==2')
  if [[ "$FREE_SPACE" -lt 13000000 ]]; then
    echo -e "\\n""$ORANGE""EMBA installation in default mode needs a minimum of 13Gig for the docker image""$NC"
    echo -e "\\n""$ORANGE""Please free enough space on /var/lib/docker""$NC"
    echo ""
    df -h || true
    echo ""
    read -p "If you know what you are doing you can press any key to continue ..." -n1 -s -r
  fi
fi

if [[ $LIST_DEP -eq 0 ]] ; then
  if ! [[ -d "external" ]] ; then
    echo -e "\\n""$ORANGE""Created external directory: ./external""$NC"
    mkdir external
    # currently this is needed for full install on Ubuntu
    # the freetz installation is running as freetzuser and needs write access:
    chown "$ORIG_USER":"$ORIG_GROUP" ./external
    chmod 777 ./external
  else
    echo -e "\\n""$ORANGE""WARNING: external directory available: ./external""$NC"
    echo -e "$ORANGE""Please remove it before proceeding ... exit now""$NC"
    exit 1
  fi

  echo -e "\\n""$ORANGE""Update package lists.""$NC"
  apt-get -y update
fi


# initial installation of the host environment:
I01_default_apps_host

DOCKER_COMP_VER=$(docker-compose -v | grep version | tr '-' ' ' | awk '{print $4}' | tr -d ',' | sed 's/^v//')
if [[ $(version "$DOCKER_COMP_VER") -lt $(version "1.28.5") ]]; then
  echo -e "\n${ORANGE}WARNING: compatibility of the used docker-compose version is unknown!$NC"
  echo -e "\n${ORANGE}Please consider updating your docker-compose installation to version 1.28.5 or later.$NC"
  echo -e "\n${ORANGE}Please check the EMBA wiki for further details: https://github.com/e-m-b-a/emba/wiki/Installation#prerequisites$NC"
  read -p "If you know what you are doing you can press any key to continue ..." -n1 -s -r
fi

if [[ "$OTHER_OS" -eq 1 ]]; then
  # UBUNTU
  if [[ "$UBUNTU_OS" -eq 1 ]]; then
    ID1_ubuntu_os
  fi
fi

INSTALL_APP_LIST=()

if [[ "$WSL" -eq 1 ]]; then
  echo "[*] Starting dockerd manually in wsl environments:"
  dockerd --iptables=false &
  sleep 3
  reset
fi

if [[ "$CVE_SEARCH" -ne 1 ]] || [[ "$DOCKER_SETUP" -ne 1 ]] || [[ "$IN_DOCKER" -eq 1 ]]; then

  I01_default_apps

  I05_emba_docker_image_dl

  IP00_extractors

  IP12_avm_freetz_ng_extract

  IP18_qnap_decryptor

  IP35_uefi_extraction

  IP61_unblob

  IP99_binwalk_default

  I02_UEFI_fwhunt

  I13_objdump

  I20_sourcecode_check

  I24_25_kernel_tools

  I108_stacs_password_search

  I110_yara_check

  I199_default_tools_github

  I120_cwe_checker

  IL10_system_emulator

  IL15_emulated_checks_init

  IF50_aggregator_common

fi

# cve-search is always installed on the host:
IF20_cve_search

cd "$HOME_PATH" || exit 1

# we reset the permissions of external from 777 back to 755:
chmod 755 ./external

if [[ "$LIST_DEP" -eq 0 ]] || [[ $IN_DOCKER -eq 0 ]] || [[ $DOCKER_SETUP -eq 1 ]] || [[ $FULL -eq 1 ]]; then
  echo -e "\\n""$MAGENTA""$BOLD""Installation notes:""$NC"
  echo -e "\\n""$MAGENTA""INFO: The cron.daily update script for EMBA is located in config/emba_updater""$NC"
  echo -e "$MAGENTA""INFO: For automatic updates it should be copied to /etc/cron.daily/""$NC"
  echo -e "$MAGENTA""INFO: For manual updates just start it via sudo ./config/emba_updater""$NC"

  echo -e "\\n""$MAGENTA""WARNING: If you plan using the emulator (-E switch) your host and your internal network needs to be protected.""$NC"

  echo -e "\\n""$MAGENTA""INFO: Do not forget to checkout current development of EMBA at https://github.com/e-m-b-a.""$NC"
fi
if [[ "$WSL" -eq 1 ]]; then
  echo -e "\\n""$MAGENTA""INFO: In the current WSL installation the docker and mongod services started manually!""$NC"
fi

if [[ "$LIST_DEP" -eq 0 ]]; then
  echo -e "$GREEN""EMBA installation finished ""$NC"
fi
