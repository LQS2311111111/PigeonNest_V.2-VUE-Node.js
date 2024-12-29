# 匿名鸽巢（2.0） - Pigeon Nest
---
### 新功能与改进
**即阅即焚**：所有消息在被接收并查看后会自动销毁，确保隐私和信息的即时性。
**去中心化通讯**：通过 WebSocket 实现去中心化的实时消息传递，不依赖传统服务器存储。
**无需用户名**：改为匿名通讯，简化用户体验。
**自定义频道加入**：用户通过输入频道号来加入不同的聊天频道，无需注册用户名。
**前端界面优化**：界面简约且现代化，优化了用户体验和界面布局。
**文件上传与分享**：支持图片和PDF文件的上传与即时分享。
---
Test_Webside实例演示:  
[https://chat.777cloud.life](https://chat.777cloud.life)
---
## 联系方式

1. Gmail邮箱:  
   `songfx.shop318318@gmail.com`
2. Telegram:  
   [https://t.me/WoeKen_viki_songfx_SHOP](https://t.me/WoeKen_viki_songfx_SHOP)
3. （付费服务）项目开发者协助部署:  
   `#可添加开发者Telegram在内交易并部署。`
---

## 项目概述

**匿名鸽巢 - Pigeon Nest** 是一个基于 **Vue.js** 和 **Node.js** 的去中心化即时通讯应用。该应用核心特点是 **即阅即焚** 功能，所有消息发送后会在查看后自动销毁，确保用户隐私和信息安全。应用采用简约的黑白配色风格，适用于实时通讯和保护用户隐私的场景。

### 主要功能

- **即时通讯**：支持文本和文件消息的实时传递。
- **即阅即焚**：所有消息在用户查看后会自动销毁。
- **去中心化**：基于 WebSocket 实现去中心化的消息传输。
- **文件上传**：支持上传图片和文档进行分享。
- **无用户名系统**：用户无需注册或登录，采用匿名方式进行交流。

---

## 技术栈

- **前端**：Vue.js 3, Socket.IO 客户端
- **后端**：Node.js, Express.js, Socket.IO 服务器
- **部署**：Nginx 作为反向代理，使用 Let's Encrypt 申请 SSL 证书

---

## 项目结构
```
chat-app/
│
├── frontend/                     # 前端项目文件
│   ├── src/                      # 前端源代码
│   │   ├── assets/               # 静态资源（例如图片、字体等）
│   │   ├── components/           # Vue.js 组件
│   │   │   ├── ChatBox.vue       # 聊天框组件
│   │   │   ├── Message.vue       # 消息组件
│   │   │   └── Input.vue         # 输入框组件
│   │   ├── views/                # 页面视图
│   │   │   ├── ChatView.vue      # 聊天页面视图
│   │   │   └── LoginView.vue     # 登录页面视图（如果有）
│   │   ├── store/                # Vuex 状态管理
│   │   │   └── store.js          # Vuex 状态管理配置文件
│   │   ├── router/               # Vue 路由配置
│   │   │   └── index.js          # 路由配置文件
│   │   ├── App.vue               # 根组件
│   │   └── main.js               # 入口文件，初始化 Vue 实例
│   ├── public/                   # 公共资源（如 index.html）
│   └── package.json              # 前端依赖
│
├── backend/                      # 后端项目文件
│   ├── app.js                    # 后端代码入口
│   ├── server.js                 # 启动服务器的文件
│   ├── routes/                   # 后端路由文件
│   │   ├── chatRoutes.js         # 聊天相关路由
│   │   └── authRoutes.js         # 验证相关路由
│   ├── controllers/              # 后端控制器
│   │   ├── chatController.js     # 聊天控制器
│   │   └── authController.js     # 验证控制器
│   ├── models/                   # 数据模型（如有数据库）
│   │   └── messageModel.js       # 消息模型（假设使用数据库）
│   ├── services/                 # 后端服务（如邮件、WebSocket）
│   │   └── websocketService.js   # WebSocket 服务
│   ├── utils/                    # 工具文件
│   │   └── auth.js               # 身份验证工具
│   └── package.json              # 后端依赖
│
└── deploy.sh                     # 自动化部署脚本
```
### 目录结构说明：
```
frontend/：前端项目文件夹，包含 Vue.js 相关的源代码和配置。
src/：前端源代码，包括组件、视图、状态管理、路由等。
public/：公共资源，如 index.html。
package.json：前端依赖文件。
backend/：后端项目文件夹，包含 Node.js 相关的代码和配置。
app.js：后端的入口文件，通常会在此配置基础服务。
server.js：启动服务器的文件。
routes/：存放后端 API 路由的文件夹。
controllers/：存放后端 API 控制器的文件夹。
models/：后端的数据库模型文件夹（如使用数据库）。
services/：后端服务代码（如 WebSocket 服务）。
utils/：工具类文件（如身份验证等工具）。
package.json：后端依赖文件。
deploy.sh：自动化部署脚本，通常用于安装依赖、配置服务器等。
```

---

## 部署步骤

### 1. 准备环境

- Ubuntu 20.04 或更高版本
- 域名（例如：`chat.777cloud.life`）
- 服务器上有 sudo(root) 权限

### 2. 执行部署脚本

1. 克隆项目到您的服务器：

```bash
ufw allow 3000   # 放行 WebSocket 服务端口
ufw allow 80     # 放行 HTTP 服务端口
ufw allow 443    # 放行 HTTPS 服务端口
git clone https://github.com/LQS2311111111/chat-app-VUE-Node.js-.git  # 拉取 GitHub 项目
cd chat-app
chmod +x deploy_install_Pigeon Nest.sh
bash deploy_install_Pigeon Nest.sh
```
2.部署脚本将自动执行以下操作：

#安装系统依赖（包括 Nginx, Node.js, Certbot 等）。
#配置并构建前端 Vue.js 项目。
#安装并配置后端 Node.js 项目。
#设置 Nginx 反向代理。
#自动申请并配置 SSL 证书。

3. 访问应用
部署完成后，您可以通过浏览器访问您的域名（例如：https://domain@test.com）来使用该应用。

4. （可选）删除 Chat-app 项目：

1.删除该项目：
```bash
chmod +x undeploy.sh
bash undeploy.sh
```

5. 常用启动代码：
   
编译前端静态文件;

```bash
npm run build // 构建静态文件
sudo cp -r dist/* /var/www/html/ // 将构建后的文件复制到 Nginx 目录
```
