# Chat App - 去中心化即时通讯

实例演示:(https://chat.777cloud.life)

这是一个基于 **Vue.js** 和 **Node.js** 的去中心化即时通讯应用，支持 **即阅即焚** 功能和实时消息传递。该应用采用简约的黑白配色，适用于需要保护用户隐私和实时通讯的场景。

## 功能概述

- **即时通讯**：用户可以进行实时文本和文件交流。
- **即阅即焚**：消息发送后会在用户查看后自动销毁。
- **密钥验证**：用户通过输入有效的密钥进行身份验证。
- **上传文件**：支持上传和分享文件。
- **去中心化**：通过 WebSocket 实现去中心化的实时消息通信。

## 技术栈

- **前端**：Vue.js 3, Socket.IO 客户端
- **后端**：Node.js, Express.js, Socket.IO 服务器
- **数据库**：暂无，未来可考虑使用数据库存储用户数据和聊天记录
- **部署**：Nginx 作为反向代理，使用 Let's Encrypt 申请 SSL 证书

## 项目结构

chat-app/│ 
            ├── frontend/ # 前端项目文件 
            │ 
            ├── src/ # 前端源代码 
            │ 
            └── package.json # 前端依赖 
            │ 
            ├── backend/ # 后端项目文件 
            │ ├── app.js # 后端代码入口 
            │ └── package.json # 后端依赖 
            │ └── deploy.sh # 自动化部署脚本


## 部署步骤

### 1. 准备环境

- Ubuntu 20.04 或更高版本
- 域名（例如：`chat.777cloud.life`）
- 服务器上有 sudo 权限

### 2. 执行部署脚本

1. 克隆项目到您的服务器：

   ```bash
   git clone https://github.com/LQS2311111111/chat-app-VUE-Node.js-.git
   cd chat-app
   bash deploy.sh

2.部署脚本将自动执行以下操作：

安装系统依赖（包括 Nginx, Node.js, Certbot 等）。
配置并构建前端 Vue.js 项目。
安装并配置后端 Node.js 项目。
设置 Nginx 反向代理。
自动申请并配置 SSL 证书。

3. 访问应用
部署完成后，您可以通过浏览器访问您的域名（例如：https://域名）来使用该应用.
