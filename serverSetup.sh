#!/bin/bash

#Validate IP Function
function validate_ip() {
    local ip=$1
    local regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

    if [[ $ip =~ $regex ]]; then
        echo "Valid IP address."
        return 0
    else
        echo "Invalid IP address."
        return 1
    fi
}

#Begin setup prompts
echo "This script will install nginx and give you the choice of installing MySQL or Postgres."
echo "It will also set up an nginx virtual host as well as certbot."
echo "and set to the IP of the server this is running on."
echo "It will also prompt you to create a database and user for whichever database type you chose."
echo "The bash history of this session will be deleted after the script is complete. \n This is for security reasons."
echo "\n"
echo "Before you continue, make sure you set up a domain or subdomain that points to this server IP."
echo "Also, if you're going to restrict database access to a specific IP address, have that on hand also"


read -n1 -p "Ready to get started? Press Y to continue, any other key to abort: " key

if [[ $key = "Y" || $key = "y" ]]; then
  echo "Continuing..."
else
  echo "Aborting..."
  exit 1
fi

#Ask if the user wants to add a new sudo user
read -p "Do you want to add a new sudo user? (y/n): " add_sudo_user

if [[ $add_sudo_user == "Y" || $add_sudo_user == "y" ]]; then
    #Prompt for the new username
    read -p "Enter the new username: " username

    #Create the new user
    sudo useradd -m $username

    while true; do
        #Prompt for the new password
        read -s -p "Enter the new password: " password
        echo
        read -s -p "Confirm the new password: " password_confirmation
        echo

        if [ "$password" == "$password_confirmation" ]; then
            break
        else
            echo "Passwords do not match. Please try again."
        fi
    done

    #Set the new user's password
    #The -e option ensures the password will expire immediately, forcing the user to set a new password the next time they log in
    echo -e "$password\n$password" | sudo passwd $username

    #Add the new user to the sudo group
    sudo usermod -aG sudo $username

    echo "New sudo user $username has been created."
else
    echo "No new sudo user created."
fi

# Install the required repositories
sudo apt-get update
sudo apt-get install -y software-properties-common
if ! sudo apt-show-versions php | grep ppa:ondrej/php; then
  # Add the PPA
  sudo add-apt-repository --ignore-failure ppa:ondrej/php
fi

sudo apt-get update

# Install PHP 8.2, FPM, cli, and PDO drivers
if ! dpkg-query -W -f='${Status}' php8.2-fpm > /dev/null; then
sudo apt-get install -y php8.2-fpm php8.2-cli php8.2-mysql php8.2-pgsql
#Install other typical PHP addons
sudo apt-get install -y php8.2-mbstring php8.2-xml php8.2-curl php8.2-gd
fi


# Install NGINX
if ! dpkg-query -W -f='${Status}' nginx > /dev/null; then
sudo apt-get install -y nginx
fi

#Install certbot
if ! dpkg-query -W -f='${Status}' certbot > /dev/null; then
sudo apt-get install -y certbot
fi

#Prompt for a domain name
read -p "Enter a domain name: " domain_name

#Create a directory for the domain
if ! [ -d /var/www/$domain_name/public ]; then
sudo mkdir /var/www/$domain_name/public
fi

# Check if the .env file already exists
if [ ! -f /var/www/$domain_name/.env ]; then
  # Create the .env file
  touch /var/www/$domain_name/.env
else
  # The .env file already exists
  echo "The .env file already exists."
fi

#Create sites-enabled and sites-available files
if ! [ -f /etc/nginx/sites-available/$domain_name ]; then
sudo cp /etc/nginx/sites-available/default /etc/nginx/sites-available/$domain_name
sudo sed -i "s/www.example.com/$domain_name/g" /etc/nginx/sites-available/$domain_name
fi

# Restart NGINX
sudo service nginx restart

# Get a certificate for the domain
if ! dpkg-query -W -f='${Status}' certbot > /dev/null; then
sudo certbot certonly --standalone -d $domain_name
fi

# Open the necessary ports in UFW
if ! ufw status | grep -q "80/tcp"; then
sudo ufw allow http
fi
if ! ufw status | grep -q "443/tcp"; then
sudo ufw allow https
fi

read -p "Would you like to install PostgreSQL or MySQL? (p/m) " install_db

#If the user wants to install PostgreSQL, install it
if [ "$install_db" = "p" ]; then

# Add the PostgreSQL APT repository
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# Import the repository signing key
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

# Update the package lists
sudo apt-get update

# Install PostgreSQL 15
sudo apt-get install -y postgresql-15

#Create a PostgreSQL user
read -p "Enter a PostgreSQL username: " postgres_username
read -s -p "Enter a PostgreSQL password: " postgres_password
read -s -p "Confirm PostgreSQL password: " postgres_password_confirmation

if [[ $postgres_password != $postgres_password_confirmation ]]; then
  echo "Passwords do not match. Please try again."
  exit 1
fi

sudo -u postgres createuser $postgres_username
sudo -u postgres psql -c "ALTER USER $postgres_username WITH PASSWORD '$postgres_password';"

#Create a PostgreSQL database
read -p "Enter a PostgreSQL database name: " postgres_database
sudo -u postgres createdb $postgres_database

#Ask the user if they want to open the Postgres port
read -p "Would you like to open the Postgres port and restrict it to a specific IP address? (y/N)\n
In the Postgres config, it will be open to all IP's but in the firewall it will be open only to the specified outside IP/n
and of cousre to the localhost. " open_postgres_port

if [ "$open_postgres_port" = "y" ]; then
	# Get the user's IP address
while true; do
    read -p "Enter your IP address: " user_ip
    validate_ip $user_ip

    if [ $? -eq 0 ]; then
        break
    else
        echo "Please try again."
    fi
done

# Add credentials to the .env file
echo "DB_NAME=$postgres_database" >> /var/www/$domain_name/.env
echo "DB_USER=$postgres_username" >> /var/www/$domain_name/.env
echo "DB_PASS=$postgres_password" >> /var/www/$domain_name/.env


# Open the Postgres port
sudo ufw allow 5432/tcp

# Add the user's IP address to the Postgres firewall rules
sudo ufw allow from $user_ip to any port 5432

# Update the PostgreSQL configuration files
sudo sed -i "s/host all all 0.0.0.0/host all all/g" /etc/postgresql/15/main/pg_hba.conf
sudo sed -i "s/listen_addresses = ''/listen_addresses = ''/g" /etc/postgresql/15/main/postgresql.conf
fi

fi
if [ "$install_db" = "m" ]; then

sudo apt-get install -y mysql-server

#Run the MySQL cleanup script
echo "Running the MySQL Secure Install"
sudo mysql_secure_installation

#Check if the user wants to open the MySQL port and restrict it to a specific IP address? (y/N) " open_mysql_port
if [ "$open_mysql_port" = "y" ]; then
	# Get the user's IP address
read -p "Enter your IP address: " user_ip

# Open the MySQL port
sudo ufw allow 3306/tcp

# Add the user's IP address to the MySQL firewall rules
sudo ufw allow from $user_ip to any port 3306

# Create a MySQL user
read -p "Enter a MySQL username: " mysql_username
read -p "Enter a MySQL password: " mysql_password
sudo mysql -u root -p << EOF
CREATE USER '$mysql_username'@'' IDENTIFIED BY '$mysql_password';
GRANT ALL PRIVILEGES ON . TO '$mysql_username'@'';
FLUSH PRIVILEGES;
EOF

# Add credentials to the .env file
echo "DB_NAME=$mysql_database" >> /var/www/$domain_name/.env
echo "DB_USER=$mysql_username" >> /var/www/$domain_name/.env
echo "DB_PASS=$mysql_password" >> /var/www/$domain_name/.env

fi
fi

echo "Do you want to install Postfix? (Y/N): "
read -n1 -p "" response

if [[ $response = "Y" || $response = "y" ]]; then
  echo "Installing Postfix..."
  sudo apt-get install postfix
else
  echo "Not installing Postfix..."
fi

#Delete the bash history of this session for security reasons.
history -c

echo "Installation complete! Your domain name is $domain_name."
exit 0