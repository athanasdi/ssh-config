#!/bin/bash

# Set the working Directory the same as the calling script deploy.sh
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"; cd "$DIR";

# IP of the server to provision 
SERVER_IP="${SERVER_IP:-192.168.1.11}"
SSH_USER="${SSH_USER:-$(whoami)}"
KEY_USER="${KEY_USER:-$(whoami)}"
DOCKER_VERSION="${DOCKER_VERSION:-1.13.0}"
SSH_DIR="${HOME}/.ssh"
SSH_FILE="${SSH_DIR}/id_rsa"


# Create user KEY_USER with no pass & sudo privileges on $SERVER_IP 
function preseed_server () {
  echo "Prepare ${KEY_USER} with sudo privileges on ${SERVER_IP}..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
        sudo adduser --disabled-password --gecos \"\" ${KEY_USER}
        sudo apt-get update && apt-get install -y -q sudo
        sudo adduser ${KEY_USER} sudo
          '"
      echo "done!"
}

# Users on group sudo can now execute sudo commands without passwd.  
function configure_sudo () {
  echo "Configuring passwordless sudo..."
  scp  "sudo/custom_sudoers" "${SSH_USER}@${SERVER_IP}:/tmp/custom_sudoers"
  ssh  -t "${SSH_USER}@${SERVER_IP}" bash -c "'
        sudo chmod 440 /tmp/custom_sudoers
        sudo chown root:root /tmp/custom_sudoers
        sudo mv /tmp/custom_sudoers /etc/sudoers.d/
          '"
  echo "done!"
}

# Generates ssh key if doesn't exists on the system
function generate_ssh_key() {
  echo "Generating ssh keys on the localhost machine..."
  echo "${SSH_FILE}"
  if [ -f "${SSH_FILE}" ] 
    then
    echo "SSH Key already exist on localhost in ${SSH_DIR}"
  else
    echo "SSH Key does not exists on localhost. Creating new ssh key in ${SSH_FILE}..."
    mkdir "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"
    ssh-keygen -t rsa -N "" -f "${SSH_FILE}"
  fi
  echo "done!"
}

function add_ssh_key() {
  echo "Adding SSH key..."
  cat  "$HOME/.ssh/id_rsa.pub" | ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
        mkdir /home/${KEY_USER}/.ssh
        cat >> /home/${KEY_USER}/.ssh/authorized_keys
        '"
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
        chmod 700 /home/${KEY_USER}/.ssh
        chmod 640 /home/${KEY_USER}/.ssh/authorized_keys
        sudo chown ${KEY_USER}:${KEY_USER} -R /home/${KEY_USER}/.ssh
          '"
  echo "done! $SERVER_IP:/home/${KEY_USER}/.ssh/authorized_keys has been updated."
}

# Disable Password Login. EnableLogin only with ssh key.
# Modifies /etc/ssh/sshd_config file with  'PasswordAuthentication no'
function configure_secure_ssh () {
  echo "Configuring secure SSH..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
        sudo sed -i.bak -r \"s/^.*PasswordAuthentication .*/PasswordAuthentication no/g\" /etc/ssh/sshd_config
        sudo systemctl restart ssh
          '"
  echo "done! $SERVER_IP: /etc/ssh/sshd_config has been updated."
}

# Install Docker:$DOCKER_VERSION on the $SERVER_IP  
function install_docker () {
  echo "Configuring Docker v${1}..."
  ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'
      sudo apt-get update
      sudo apt-get install -y -q libapparmor1 aufs-tools ca-certificates
      wget -O "docker.deb https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_${1}-0~"$(uname -n)"-"$(lsb_release -cs)"_amd64.deb"
      sudo dpkg -i docker.deb
      rm docker.deb
      sudo usermod -aG docker "${KEY_USER}"
      '"
  echo "done!"
}

# Pull The required images listed in $DOCKER_PULL_IMAGES
function docker_pull () {
  echo "Pulling Docker images..."
  for image in "${DOCKER_PULL_IMAGES[@]}"
  do
    ssh -t "${SSH_USER}@${SERVER_IP}" bash -c "'docker pull ${image}'"
  done
  echo "done!"
}

# Do all the stuff to provision the server, except preseed_server
function provision_server () {
  configure_sudo
  echo "---"
  generate_ssh_key
  echo "---"
  add_ssh_key
  echo "---"
  configure_secure_ssh
  echo "---"
  install_docker ${1}
  echo "---"
  docker_pull
  echo "---"
  
}


function help_menu () {
cat << EOF
Usage: ${0} (-h | -S | -P | -u | -k | -g |  -s | -d [docker_ver] | -l | -a [docker_ver])

ENVIRONMENT VARIABLES:

   SERVER_IP        IP address to work on, ie. staging or production
                    Defaulting to ${SERVER_IP}

   SSH_USER         User account to ssh and scp in as
                    Defaulting to ${SSH_USER}

   KEY_USER         User account linked to the SSH key
                    Defaulting to ${KEY_USER}

   DOCKER_VERSION   Docker version to install
                    Defaulting to ${DOCKER_VERSION}

OPTIONS:
   -h|--help                 Show this message
   -S|--preseed-server       Preseed intructions for the staging server
   -u|--sudo                 Configure passwordless sudo
   -k|--ssh-key              Add SSH key
   -g|--ssh-gen              Generate SSH key if does not already exists
   -s|--ssh                  Configure secure SSH
   -d|--docker               Install Docker
   -l|--docker-pull          Pull necessary Docker images
   -a|--all                  Provision everything except preseeding

EXAMPLES:

   Pressed user $KEY_USER with sudo privileges
        $ deploy -S

   Configure passwordless sudo:
        $ deploy -u

   Add SSH key:
        $ deploy -k

   Generate SSH Key on localhost if not exists:
        $ deploy -g 

   Configure secure SSH:
        $ deploy -s

   Install Docker v${DOCKER_VERSION}:
        $ deploy -d

   Install custom Docker version:
        $ deploy -d 1.8.1

   Pull necessary Docker images:
        $ deploy -l

   Configure everything together:
        $ deploy -a

   Configure everything together with a custom Docker version:
        $ deploy -a 1.10.1
EOF
}


while [[ $# > 0 ]]
do
case "${1}" in
  -S|--preseed-server)
  preseed_server
  shift
  ;;
  -u|--sudo)
  configure_sudo
  shift
  ;;
  -k|--ssh-key)
  add_ssh_key
  shift
  ;;
  -g|--ssh-gen)
  generate_ssh_key
  shift
  ;;
  -s|--ssh)
  configure_secure_ssh
  shift
  ;;
  -d|--docker)
  install_docker "${2:-${DOCKER_VERSION}}"
  shift
  ;;
  -l|--docker-pull)
  docker_pull
  shift
  ;;
  -a|--all)
  provision_server "${2:-${DOCKER_VERSION}}"
  shift
  ;;
  -h|--help)
  help_menu
  shift
  ;;
  *)
  echo "${1} is not a valid flag, try running: ${0} --help"
  ;;
esac
shift
done
