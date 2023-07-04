#!/bin/bash

# Function to ask for user confirmation
function ask() {
    local prompt default reply

    if [[ "${2:-}" = "Y" ]]; then
        prompt="Y/n"
        default=Y
    elif [[ "${2:-}" = "N" ]]; then
        prompt="y/N"
        default=N
    else
        prompt="y/n"
        default=
    fi

    while true; do
        echo -e "$1 [$prompt] "
        read reply

        if [[ -z "$reply" ]]; then
            reply=$default
        fi

        reply=$(echo "$reply" | tr '[:upper:]' '[:lower:]')

        if [[ "$reply" = 'y' ]]; then
            return 0
        elif [[ "$reply" = 'n' ]]; then
            return 1
        else
            echo "Invalid input. Please choose Y or N only."
        fi
    done
}

#Validate IP Function
function validate_ip() {
    local ip=$1
    local regex='^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'

    if [[ $ip =~ $regex ]]; then
        echo -e "Valid IP address."
        return 0
    else
        echo -e "Invalid IP address."
        return 1
    fi
}

#Update ENV Function
function update_env() {
    local env_file=$1
    local key=$2
    local value=$3

    # Check if the file exists, if not create it
    if [ ! -f "$env_file" ]; then
        touch "$env_file"
    fi

    # Check if the key exists in the file
    if grep -q "^$key=" "$env_file"; then
        # If the key exists, replace it
        sed -i "s/^$key=.*/$key=$value/" "$env_file"
    else
        # If the key does not exist, append it
        echo -e "$key=$value" >> "$env_file"
    fi
}

#Begin setup prompts
echo -e "This script will install nginx and give you the choice of installing MySQL or Postgres."
echo -e "It will also set up an nginx virtual host as well as certbot."
echo -e "and set to the IP of the server this is running on."
echo -e "It will also prompt you to create a database and user for whichever database type you chose."
echo -e "The bash history of this session will be deleted after the script is complete. \n This is for security reasons."
echo -e ""
echo -e "Before you continue, make sure you set up a domain or subdomain that points to this server IP."
echo -e "Also, if you're going to restrict database access to a specific IP address, have that on hand also"


read -n1 -p "Ready to get started? Press Y to continue, any other key to abort: " key

if [[ $key = "Y" || $key = "y" ]]; then
  echo -e "\nContinuing..."
else
  echo -e "\nAborting..."
  exit 1
fi

#Ask if the user wants to add a new sudo user
read -p "Do you want to add a new sudo user? (y/n): " add_sudo_user

if [[ $add_sudo_user == "Y" || $add_sudo_user == "y" ]]; then
    #Prompt for the new username
    read -r -p "Enter the new username: " username

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
            echo -e "Passwords do not match. Please try again."
        fi
    done

    #Set the new user's password
    #The -e option ensures the password will expire immediately, forcing the user to set a new password the next time they log in
    echo -e "$password\n$password" | sudo passwd $username

    #Add the new user to the sudo group
    sudo usermod -aG sudo $username

    echo -e "New sudo user $username has been created."
else
    echo -e "No new sudo user created."
fi

echo "Adding Locale so that the PHP repo install doesn't complain..."
sudo localectl set-locale LANG=en_US.UTF-8
sudo locale-gen

# Install the required repositories
sudo apt-get update
sudo apt-get install -y software-properties-common
if ! sudo apt-show-versions php | grep ppa:ondrej/php; then
  # Add the PPA
  sudo add-apt-repository ppa:ondrej/php
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
sudo apt-get install -y python3-certbot-nginx
fi

#Prompt for a domain name
read -r -p "Enter a domain name: " domain_name

# Create a directory for the domain
if ! [ -d /var/www/"$domain_name"/public ]; then
  sudo mkdir -p /var/www/"$domain_name"/public
fi

# Change ownership to www-data:www-data
sudo chown -R www-data:www-data /var/www/"$domain_name"/public

# Set the sticky bit so that the group ownership of future files/directories remains the same
sudo chmod g+s /var/www/$domain_name/public

# Change directory permissions
find /var/www/html -type d -exec chmod 755 {} \;

# Change file permissions
find /var/www/html -type f -exec chmod 644 {} \;

# Check if the .env file already exists
if [ ! -f /var/www/$domain_name/.env ]; then
  # Create the .env file
  touch /var/www/$domain_name/.env
else
  # The .env file already exists
  echo -e "Skipping - The .env file already exists."
fi

env_file="/var/www/$domain_name/.env"

#Remove the default nginx file and the symlink to it
echo "Removing default nginx default files..."
if [ -f /etc/nginx/sites-enabled/default ]; then
  sudo rm /etc/nginx/sites-enabled/default
fi

if [ -f /etc/nginx/sites-available/default ]; then
  sudo rm /etc/nginx/sites-available/default
fi

#Create sites-enabled and sites-available files
if ! [ -f /etc/nginx/sites-available/$domain_name ]; then
  sudo bash -c "cat > /etc/nginx/sites-available/$domain_name" << EOF
server {
    listen 80;
    server_name $domain_name;
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    #listen 443 ssl;
    server_name $domain_name;

    root /var/www/$domain_name/public;
    index index.php index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
fi

# Create a symlink to the sites-enabled file
if ! [ -f /etc/nginx/sites-enabled/$domain_name ]; then
  sudo ln -s /etc/nginx/sites-available/$domain_name /etc/nginx/sites-enabled/$domain_name
fi

# Restart NGINX
sudo service nginx restart

# Get a certificate for the domain
if dpkg-query -W -f='${Status}' certbot > /dev/null; then
  echo "Getting a certificate for the domain..."
sudo certbot --nginx -d $domain_name
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
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/postgresql.gpg >/dev/null

# Update the package lists
sudo apt-get update

# Install PostgreSQL 15
sudo apt-get install -y postgresql-15

#Create a PostgreSQL user
read -r -p "Enter a PostgreSQL username: " postgres_username
echo ""
read -s -r -p "Enter a PostgreSQL password: " postgres_password
echo ""
read -s -r -p "Confirm PostgreSQL password: " postgres_password_confirmation
echo ""

if [[ $postgres_password != $postgres_password_confirmation ]]; then
  echo -e "Passwords do not match. Please try again."
  exit 1
fi

cd /tmp || exit
sudo -u postgres createuser $postgres_username
sudo -u postgres psql -c "ALTER USER $postgres_username WITH PASSWORD '$postgres_password';"
cd - || exit

#Create a PostgreSQL database
read -r -p "Enter a PostgreSQL database name: " postgres_database
sudo -u postgres createdb $postgres_database

#Ask the user if they want to open the Postgres port
echo -e "Opening the Postgres port will allow you to connect to the database remotely."
echo -e "Opening it to a specific IP will allow a database management tool to control it."
echo -e "If you don't want to do that, you can always open the port later."
ask "Would you like to open the Postgres port and restrict it to a specific IP address (Y/N)?" Y && open_postgres_port=true || open_postgres_port=false

if $open_postgres_port; then
	# Get the user's IP address
while true; do
    read -r -p "Enter your IP address: " user_ip
    validate_ip $user_ip

    if [ $? -eq 0 ]; then
        break
    else
        echo -e "Please try again."
    fi
done

# Add credentials to the .env file
update_env "$env_file" "DB_NAME" "$postgres_database"
update_env "$env_file" "DB_USER" "$postgres_username"
update_env "$env_file" "DB_PASS" "$postgres_password"


# Open the Postgres port
sudo ufw allow 5432/tcp

# Add the user's IP address to the Postgres firewall rules
sudo ufw allow from $user_ip to any port 5432

# Update the PostgreSQL configuration files
sudo sed -i "s/host all all 127.0.0.1\/32 scram-sha-256/host all all 0.0.0.0\/0 scram-sha-256/g" /etc/postgresql/15/main/pg_hba.conf
sudo sed -i '/listen_addresses/c\listen_addresses = '\''*'\''' /etc/postgresql/15/main/postgresql.conf

# Restart PostgreSQL
sudo service postgresql restart

fi

fi
if [ "$install_db" = "m" ]; then

sudo apt-get install -y mysql-server

#Run the MySQL cleanup script
echo -e "Running the MySQL Secure Install"
sudo mysql_secure_installation

#Check if the user wants to open the MySQL port
ask "Would you like to open the MySQL port and restrict it to a specific IP address (Y/N)?" Y && open_msyql_port=true || open_mysql_port=false

if $open_mysql_port; then
	# Get the user's IP address
read -p "Enter your IP address: " user_ip

# Open the MySQL port
sudo ufw allow 3306/tcp

# Add the user's IP address to the MySQL firewall rules
sudo ufw allow from $user_ip to any port 3306

# Create a MySQL user
read -r -p "Enter a MySQL username: " mysql_username
read -s -r -p "Enter a MySQL password: " mysql_password
echo
read -r -p "Enter a MySQL database name: " mysql_database

sudo mysql -u root -p << EOF
CREATE USER '$mysql_username'@'localhost' IDENTIFIED BY '$mysql_password';
CREATE DATABASE IF NOT EXISTS $mysql_database;
GRANT ALL PRIVILEGES ON $mysql_database.* TO '$mysql_username'@'localhost';
FLUSH PRIVILEGES;
EOF

# Add credentials to the .env file
update_env "$env_file" "DB_NAME" "$mysql_database"
update_env "$env_file" "DB_USER" "$mysql_username"
update_env "$env_file" "DB_PASS" "$mysql_password"

fi
fi


ask "Would you like to install Postfix?" Y && install_postfix=true || install_postfix=false

if $install_postfix; then
  echo -e "Installing Postfix..."
  sudo apt-get install postfix
else
  echo -e "Not installing Postfix..."
fi

#Delete the bash history of this session for security reasons.
echo -e "Deleting bash history for this session for security reasons"
history -c

#Install vim plugin ability
echo -e "vim can now use plugins, but we're not installing any."
if [ ! -f ~/.vim/autoload/plug.vim ]; then
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

#Adds line numbers to vim.
echo "Adding configuration options to vim."
echo -e "Adding various options to vim. See ~/.vimrc for details."
if ! grep -q "set number" ~/.vimrc; then
  echo -e "set number" >> ~/.vimrc
fi
if ! grep -q "syntax on" ~/.vimrc; then
  echo -e "syntax on" >> ~/.vimrc
fi
if ! grep -q "set mouse=a" ~/.vimrc; then
  echo -e "set mouse=a" >> ~/.vimrc
fi
if ! grep -q "set showmatch" ~/.vimrc; then
  echo -e "set showmatch" >> ~/.vimrc
fi
if ! grep -q "set cursorline" ~/.vimrc; then
  echo -e "set cursorline" >> ~/.vimrc
fi
if ! grep -q "autocmd BufReadPost \* if line(\"'\\\"\") >= 1 && line(\"'\\\"\") <= line(\"\$\") | exe \"normal! g'\\\"\" | endif" ~/.vimrc; then
  echo -e "autocmd BufReadPost * if line(\"'\\\"\") >= 1 && line(\"'\\\"\") <= line(\"\$\") | exe \"normal! g'\\\"\" | endif" >> ~/.vimrc
fi
if ! grep -q "set linebreak" ~/.vimrc; then
  echo -e "set linebreak" >> ~/.vimrc
fi
if ! grep -q "set title" ~/.vimrc; then
  echo -e "set title" >> ~/.vimrc
fi
if ! grep -q "set scrolloff=1" ~/.vimrc; then
  echo -e "set scrolloff=1" >> ~/.vimrc
fi
if ! grep -q "set sidescrolloff=1" ~/.vimrc; then
  echo -e "set sidescrolloff=1" >> ~/.vimrc
fi
if ! grep -q "set noswapfile" ~/.vimrc; then
  echo -e "set noswapfile" >> ~/.vimrc
fi
if ! grep -q "filetype on" ~/.vimrc; then
  echo -e "filetype on" >> ~/.vimrc
fi
if ! grep -q "filetype plugin on" ~/.vimrc; then
  echo -e "filetype plugin on" >> ~/.vimrc
fi
echo -e "Installation complete! Your domain name is $domain_name."
exit 0