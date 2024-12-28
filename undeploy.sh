#!/bin/bash

# 定义目录和配置
PROJECT_ROOT="/var/www/chat-app"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BACKEND_DIR="$PROJECT_ROOT/backend"
DOMAIN="chat.777cloud.life"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
NGINX_CONF="/etc/nginx/sites-available/chat-app"
NGINX_ENABLED_CONF="/etc/nginx/sites-enabled/chat-app"

# 1. 停止 PM2 后端进程
echo "1. 停止 PM2 后端进程..."
pm2 stop chat-backend
pm2 delete chat-backend
pm2 save
echo "PM2 后端进程已停止并删除。"

# 2. 删除前端和后端文件
echo "2. 删除项目文件..."
if [ -d "$PROJECT_ROOT" ]; then
  sudo rm -rf "$PROJECT_ROOT"
  echo "项目文件已删除。"
else
  echo "未找到项目目录: $PROJECT_ROOT"
fi

# 3. 删除 Nginx 配置
echo "3. 删除 Nginx 配置..."
if [ -f "$NGINX_CONF" ]; then
  sudo rm -f "$NGINX_CONF"
  echo "Nginx 配置文件已删除。"
else
  echo "未找到 Nginx 配置文件: $NGINX_CONF"
fi

# 删除符号链接
if [ -f "$NGINX_ENABLED_CONF" ]; then
  sudo rm -f "$NGINX_ENABLED_CONF"
  echo "Nginx 启用的配置链接已删除。"
else
  echo "未找到启用的 Nginx 配置链接: $NGINX_ENABLED_CONF"
fi

# 4. 删除 SSL 证书
echo "4. 删除 SSL 证书..."
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  sudo rm -rf "/etc/letsencrypt/live/$DOMAIN"
  sudo rm -rf "/etc/letsencrypt/archive/$DOMAIN"
  sudo rm -rf "/etc/letsencrypt/renewal/$DOMAIN.conf"
  echo "SSL 证书已删除。"
else
  echo "未找到 SSL 证书目录: /etc/letsencrypt/live/$DOMAIN"
fi

# 5. 删除 Certbot 自动更新任务
echo "5. 删除 Certbot 自动更新任务..."
sudo sed -i '/certbot renew/d' /etc/crontab
echo "Certbot 自动更新任务已删除。"

# 6. 删除 Nginx 服务和配置
echo "6. 删除 Nginx 服务..."
sudo systemctl stop nginx
sudo systemctl disable nginx
sudo apt remove --purge nginx nginx-common -y
sudo apt autoremove -y
echo "Nginx 服务及其配置已删除。"

# 7. 删除 Node.js 和 PM2
echo "7. 删除 Node.js 和 PM2..."
sudo npm uninstall -g pm2
sudo apt remove --purge nodejs npm -y
sudo apt autoremove -y
echo "Node.js 和 PM2 已删除。"

# 8. 完成删除
echo "========== 删除完成 =========="
echo "项目、服务、配置文件及证书已被完全删除。"
