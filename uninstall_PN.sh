#!/bin/bash

# 脚本描述
# 完整卸载 "匿名鸽巢 - Pigeon Nest" 项目部署环境，包括项目文件、依赖服务和 SSL 证书等。

# 确认用户身份
if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户权限运行此脚本。"
  exit 1
fi

# 停止相关服务
echo "[1/7] 停止所有相关服务..."
pm2 stop all && pm2 delete all
if [ $? -eq 0 ]; then
  echo "已成功停止服务。"
else
  echo "服务停止可能失败，请检查 pm2 状态。"
fi

# 删除项目文件
echo "[2/7] 删除项目目录 /var/www/chat-app..."
PROJECT_DIR="/var/www/chat-app"
if [ -d "$PROJECT_DIR" ]; then
  rm -rf "$PROJECT_DIR"
  if [ ! -d "$PROJECT_DIR" ]; then
    echo "项目文件已成功删除。"
  else
    echo "项目文件删除失败，请手动检查。"
  fi
else
  echo "项目目录不存在，跳过此步骤。"
fi

# 清理上传目录
echo "[3/7] 清理用户上传文件..."
UPLOAD_DIR="/var/www/chat-app/uploads"
if [ -d "$UPLOAD_DIR" ]; then
  rm -rf "$UPLOAD_DIR"
  if [ ! -d "$UPLOAD_DIR" ]; then
    echo "上传目录已成功清理。"
  else
    echo "上传目录清理失败，请手动检查。"
  fi
else
  echo "上传目录不存在，跳过此步骤。"
fi

# 删除 Nginx 配置
echo "[4/7] 删除 Nginx 配置文件..."
NGINX_CONF="/etc/nginx/sites-available/pigeon-nest.conf"
NGINX_LINK="/etc/nginx/sites-enabled/pigeon-nest.conf"
if [ -f "$NGINX_CONF" ]; then
  rm -f "$NGINX_CONF"
  echo "已删除 Nginx 配置文件。"
else
  echo "未找到 Nginx 配置文件，跳过此步骤。"
fi
if [ -L "$NGINX_LINK" ]; then
  rm -f "$NGINX_LINK"
  echo "已删除 Nginx 符号链接。"
else
  echo "未找到 Nginx 符号链接，跳过此步骤。"
fi

# 重载 Nginx
echo "重载 Nginx 服务..."
systemctl reload nginx
if [ $? -eq 0 ]; then
  echo "Nginx 已成功重载。"
else
  echo "Nginx 重载可能失败，请检查配置文件状态。"
fi

# 删除 SSL 证书
echo "[5/7] 删除 Certbot 证书..."
read -p "请输入为此项目申请的域名（如 chat.777cloud.life）：" DOMAIN_NAME
if [ ! -z "$DOMAIN_NAME" ]; then
  certbot delete --cert-name "$DOMAIN_NAME"
  if [ $? -eq 0 ]; then
    echo "SSL 证书已成功删除。"
  else
    echo "删除 SSL 证书失败，请手动检查 Certbot 状态。"
  fi
else
  echo "未输入域名，跳过 SSL 证书删除。"
fi

# 可选：卸载依赖
echo "[6/7] 卸载项目相关依赖（可选）..."
read -p "是否卸载 Node.js, pm2, Nginx 和 Certbot 相关工具？[y/N]: " UNINSTALL_DEPENDENCIES
if [[ "$UNINSTALL_DEPENDENCIES" =~ ^[Yy]$ ]]; then
  apt-get remove --purge -y nodejs nginx certbot
  apt-get autoremove -y
  echo "依赖工具已卸载。"
else
  echo "跳过依赖卸载步骤。"
fi

# 验证清理是否成功
echo "[7/7] 检查清理结果..."
if [ ! -d "$PROJECT_DIR" ] && [ ! -d "$UPLOAD_DIR" ] && [ ! -f "$NGINX_CONF" ]; then
  echo "卸载脚本执行完成，部署环境已成功清理。"
else
  echo "清理未完全，请手动检查相关文件和配置。"
fi

exit 0
