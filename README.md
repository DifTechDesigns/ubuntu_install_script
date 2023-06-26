# ubuntu_install_script
Install script for Ubuntu server that installs nginx, php, the choice between mySQL and Postgres as well as postfix.
Overview
This bash script is designed to automate the installation and setup process for a server running on Ubuntu 22.04. It installs and configures NGINX, PHP, Certbot and gives an option to install either PostgreSQL or MySQL.

What it Does
Here is an outline of what the script will do:

Prompt the user if they want to add a new sudo user and if yes, it takes a username and password as input.

Set the server locale to en_US.UTF-8.

Install required repositories and PHP 8.2 with some additional PHP modules.

Install NGINX and Certbot for SSL certification.

Ask for the domain name, set up an NGINX server block for it, acquire SSL certificates using Certbot, and open necessary ports (80 and 443) in UFW (Uncomplicated Firewall).

Based on the user's choice, install either PostgreSQL or MySQL and create a new user and database.

Optional: It can open the Postgres or MySQL port and restrict it to a specific IP address.

Requirements
Ubuntu 22.04 server.
Root or sudo access to the server.
Domain or subdomain pointing to your server's IP.
The script is expected to be run on a fresh server.
Usage
Copy the script to your server.

Make it executable with the following command:
chmod +x scriptname.sh

Run the script as a user with sudo privileges or as the root user:
sudo ./scriptname.sh

Follow the prompts on the screen to install and configure the required software.

Warnings
This script will delete the bash history after it is run. This is a security measure to avoid exposing any sensitive data that might be logged during the script's execution.
Ensure you have a backup of any important data before running the script.
Be careful when entering sensitive information like passwords and IP addresses, as incorrect inputs could cause problems.

Maintenance
This script is known to work on Ubuntu 22.04 and has been tested on a DigitalOcean droplet. If you encounter any issues, please submit a bug report or pull request. It is recommended to keep the system updated and check the script for updates regularly to ensure compatibility with the latest software versions.

Pull requests that improve the script are always welcome.
