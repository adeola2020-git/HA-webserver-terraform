#!/bin/bash
sudo yum update -y
sudo yum install httpd -y
sudo systemctl start httpd
sudo systemctl status httpd
sudo systemctl enable httpd
echo "<html><body><h1>Hello world! This is web server $(hostname -f)</h1></body></html>" > /var/www/html/index.html
