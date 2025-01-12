#!/bin/bash

# 定义全局域名引用
echo "输入您解析好的域名:"
read DOMAIN

# 定义目录和配置
PROJECT_ROOT="/var/www/chat-app"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
BACKEND_DIR="$PROJECT_ROOT/backend"
DOMAIN="$DOMAIN"
SSL_CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
SSL_KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

echo "========== 部署脚本启动 =========="

# 1. 更新系统并安装必要依赖
echo "1. 更新系统..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y nginx nodejs npm git build-essential curl certbot python3-certbot-nginx

# 2. 安装最新的 Node.js LTS 版本
echo "2. 安装 Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# 3. 安装 PM2
echo "3. 安装 PM2..."
sudo npm install -g pm2

# 4. 创建项目目录
echo "4. 创建项目目录..."
sudo mkdir -p "$FRONTEND_DIR" "$BACKEND_DIR"
sudo chown -R $USER:$USER "$PROJECT_ROOT"

# 5. 写入前端代码
echo "5. 写入前端代码..."
cat > "$FRONTEND_DIR/package.json" <<EOF
{
  "name": "chat-app-frontend",
  "version": "1.0.0",
  "scripts": {
    "serve": "vue-cli-service serve",
    "build": "vue-cli-service build",
    "start": "npm run serve"
  },
  "dependencies": {
    "@fortawesome/fontawesome-free": "^6.7.2",
    "axios": "^1.7.9",
    "socket.io-client": "^4.0.0",
    "vue": "^3.5.13",
    "vue-meta": "^2.4.0",
    "vue-router": "^4.5.0",
    "vuex": "^4.1.0"
  },
  "devDependencies": {
    "@vue/cli-service": "^5.0.8"
  },
  "main": "index.js",
  "keywords": [],
  "author": "",
  "license": "ISC",
  "description": ""
}
EOF

mkdir -p "$FRONTEND_DIR/src"

cat > "$FRONTEND_DIR/src/main.js" <<EOF
// 引入 Vue 和 App
import { createApp } from 'vue';
import App from './App.vue';

// 设置页面标题
document.title = "匿名鸽巢 - Pigeon Nest";
createApp(App).mount('#app');
EOF

cat > "$FRONTEND_DIR/src/App.vue" <<EOF
<template>
  <div id="app" class="chat-container">
    <div v-if="!isChannelValid" class="key-container">
      <input v-model="channel" type="text" class="key-input" placeholder="请输入频道号" />
      <button @click="joinChannel" class="key-button">加入频道</button>
      <div v-if="channelError" class="error-message">请输入有效的频道号。</div>
    </div>
    <div v-else>
      <div class="header">匿名鸽巢 - Pigeon Nest - 频道：{{ channel }}</div>
      <div class="messages">
        <div
          v-for="(msg, index) in messages"
          :key="msg.id"
          class="message"
          :class="{ 'sent': msg.sender === 'self', 'received': msg.sender !== 'self' }"
        >
          <div class="sender-name" v-if="msg.senderName">{{ msg.senderName }}</div>
          <div class="message-content">
            <span v-if="msg.type === 'text'">{{ msg.text }}</span>
            <div v-else-if="msg.type === 'file'">
              <img
                v-if="msg.localPreview || (msg.fileUrl && /\.(png|jpe?g)$/i.test(msg.fileUrl))"
                :src="msg.localPreview || msg.fileUrl"
                alt="file preview"
                class="file-preview"
              />
              <a v-else :href="msg.fileUrl" target="_blank" class="file-link">
                {{ msg.fileName }}
              </a>
            </div>
          </div>
        </div>
      </div>
      <div class="input-container">
        <input
          v-model="newMessage"
          placeholder="输入消息..."
          @keyup.enter="sendMessage"
          class="input-box"
        />
        <button @click="triggerFileUpload" class="upload-button">上传文件</button>
        <input type="file" ref="fileInput" @change="handleFileUpload" class="file-input" style="display: none;" />
      </div>
    </div>
  </div>
</template>

<script>
import { io } from "socket.io-client";
import axios from "axios";

export default {
  data() {
    return {
      channel: "",
      isChannelValid: false,
      channelError: false,
      newMessage: "",
      messages: [],
      socket: null,
    };
  },
  methods: {
    joinChannel() {
      if (!this.channel.trim()) {
        this.channelError = true;
        return;
      }
      this.channelError = false;
      this.socket.emit("joinChannel", this.channel);
      this.isChannelValid = true;

      // 监听文本消息和文件消息
      this.socket.on("message", this.handleIncomingMessage);
      this.socket.on("fileMessage", this.handleIncomingMessage);
    },

    handleIncomingMessage(msg) {
      if (msg.channel === this.channel && !this.messages.some((m) => m.id === msg.id)) {
        this.messages.push(msg); // 添加消息
        this.scheduleMessageDeletion(msg); // 删除过期消息
      }
    },

    sendMessage() {
      if (!this.newMessage.trim()) return;

      const msg = {
        id: Date.now(),
        text: this.newMessage,
        sender: "self",
        type: "text",
        channel: this.channel,
        expirationTime: Date.now() + 30000,
      };

      this.messages.push(msg); // 本地显示消息
      this.socket.emit("message", msg); // 通过 Socket 广播
      this.newMessage = ""; // 清空输入框
      this.scheduleMessageDeletion(msg);
    },

    triggerFileUpload() {
      this.$refs.fileInput.click();
    },

    handleFileUpload(event) {
      const file = event.target.files[0];
      if (!file) return;

      const allowedTypes = ["image/jpeg", "image/png"];
      const maxSizeMB = 10;

      if (!allowedTypes.includes(file.type) || file.size > maxSizeMB * 1024 * 1024) {
        alert("请上传小于 10MB 的图片文件！");
        this.$refs.fileInput.value = "";
        return;
      }

      const reader = new FileReader();
      reader.onload = (e) => {
        const previewUrl = e.target.result;
        const msg = {
          id: Date.now(),
          sender: "self",
          type: "file",
          fileName: file.name,
          localPreview: previewUrl,
          expirationTime: Date.now() + 30000,
          channel: this.channel,
        };

        this.messages.push(msg); // 添加本地预览
        this.scheduleMessageDeletion(msg);

        const formData = new FormData();
        formData.append("upload", file);

        // 上传文件到服务器
        axios
          .post("https://chat.777cloud.life/upload", formData, {
            headers: { "Content-Type": "multipart/form-data" },
          })
          .then((response) => {
            msg.fileUrl = response.data.fileUrl; // 服务器返回的 URL
            msg.localPreview = null; // 替换本地预览为服务器 URL
            this.socket.emit("fileMessage", msg); // 广播文件消息
          })
          .catch((error) => {
            alert("文件上传失败，请重试！");
            console.error(error);
          })
          .finally(() => {
            this.$refs.fileInput.value = "";
          });
      };

      reader.readAsDataURL(file); // 文件预览
    },

    scheduleMessageDeletion(msg) {
      setTimeout(() => {
        this.messages = this.messages.filter((m) => m.id !== msg.id);
      }, msg.expirationTime - Date.now());
    },
  },
  created() {
    this.socket = io("https://chat.777cloud.life");
  },
};
</script>

<style scoped>
/* 样式：全局容器 */
.chat-container {
  font-family: 'Arial', sans-serif;
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #1f1b2e; /* 黑紫色背景 */
  color: white; /* 文字颜色为白色 */
  font-size: 16px;
}

/* 频道号输入页面 */
.key-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
  flex-direction: column;
}

.key-input {
  padding: 15px;
  font-size: 18px;
  border-radius: 20px;
  border: 1px solid #ccc;
  margin-bottom: 20px;
  width: 300px;
  text-align: center;
}

.key-button {
  padding: 15px 30px;
  background-color: #7a4dff; /* 紫色 */
  color: white;
  border: none;
  border-radius: 20px;
  cursor: pointer;
  font-size: 16px;
}

.key-button:hover {
  background-color: #5b39b7; /* 深紫色 */
}

.error-message {
  color: red;
  font-size: 14px;
  margin-top: 10px;
}

/* 头部样式 */
.header {
  padding: 20px;
  background-color: #111;
  color: white;
  text-align: center;
  font-size: 20px;
  font-weight: bold;
  border-bottom: 2px solid #444;
}

/* 消息列表 */
.messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  background-color: #2c2a3c; /* 深紫色背景 */
  display: flex;
  flex-direction: column;
  gap: 10px;
  max-height: calc(100vh - 160px);
}

/* 消息气泡 */
.message {
  display: flex;
  flex-direction: column;
  max-width: 70%;
  padding: 10px;
  border-radius: 10px;
}

.sent {
  background-color: #7a4dff; /* 紫色 */
  align-self: flex-end;
}

.received {
  background-color: #444; /* 深灰 */
  align-self: flex-start;
}

.sender-name {
  font-size: 12px;
  font-weight: bold;
  color: #ccc;
}

.message-content {
  font-size: 14px;
  word-wrap: break-word;
}

.file-preview {
  max-width: 150px;
  max-height: 150px;
  object-fit: cover;
  border-radius: 5px;
}

.input-container {
  padding: 20px;
  background-color: #1b1b2f;
  display: flex;
  align-items: center;
  gap: 10px;
}

.input-box {
  flex-grow: 1;
  padding: 10px;
  font-size: 16px;
  border-radius: 20px;
  border: none;
  background-color: #333;
  color: white;
}

.send-button, .upload-button {
  padding: 10px 20px;
  background-color: #7a4dff;
  color: white;
  border: none;
  border-radius: 20px;
  cursor: pointer;
}

.send-button:hover, .upload-button:hover {
  background-color: #5b39b7;
}

/* GitHub 图标 */
.github-button {
  position: absolute;
  top: 20px;
  right: 20px;
  font-size: 24px;
  color: white;
}
</style>
EOF

echo "创建后端 app.js 文件..."
cat > "$BACKEND_DIR/app.js" <<'EOF'
const express = require('express');
const https = require('https');
const fs = require('fs');
const path = require('path');
const socketIo = require('socket.io');
const fileUpload = require('express-fileupload');

// SSL 证书配置
const privateKey = fs.readFileSync('/etc/letsencrypt/live/chat.777cloud.life/privkey.pem', 'utf8');
const certificate = fs.readFileSync('/etc/letsencrypt/live/chat.777cloud.life/fullchain.pem', 'utf8');
const ca = fs.readFileSync('/etc/letsencrypt/live/chat.777cloud.life/chain.pem', 'utf8');
const credentials = { key: privateKey, cert: certificate, ca: ca };

// 初始化服务
const app = express();
const server = https.createServer(credentials, app);
const io = socketIo(server);

// 静态文件目录，服务 Vue 编译后的文件
const buildDir = path.join('/var/www/chat-app/frontend', 'dist');

// 检查目录是否存在
if (!fs.existsSync(buildDir)) {
  console.error('构建目录不存在，请检查 Vue 项目的 dist 目录');
} else {
  app.use(express.static(buildDir));
}

// 文件上传目录
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// 中间件配置
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(
  fileUpload({
    limits: { fileSize: 10 * 1024 * 1024 }, // 限制文件大小为 10MB
  })
);
app.use('/upload', express.static(uploadDir)); // 让上传文件通过访问路径可以读取

// 文件上传接口
app.post('/upload', (req, res) => {
  const file = req.files?.upload;
  if (!file) {
    return res.status(400).json({ error: '未检测到文件上传！' });
  }

  const allowedTypes = ['image/jpeg', 'image/png'];
  if (!allowedTypes.includes(file.mimetype)) {
    return res.status(400).json({ error: '不支持的文件类型！' });
  }

  const fileName = Date.now() + '-' + file.name.replace(/\s+/g, '_');
  const filePath = path.join(uploadDir, fileName);

  file.mv(filePath, (err) => {
    if (err) {
      return res.status(500).json({ error: '文件上传失败！' });
    }
    res.json({ fileUrl: `https://chat.777cloud.life/upload/${fileName}` });
  });
});

// WebSocket 处理
io.on('connection', (socket) => {
  console.log('新客户端已连接');

  socket.on('joinChannel', (channel) => {
    socket.join(channel); // 客户端加入频道
    console.log(`客户端加入频道：${channel}`);
  });

  socket.on('message', (msg) => {
    console.log('接收到消息：', msg);
    io.to(msg.channel).emit('message', msg); // 广播消息
  });

  socket.on('fileMessage', (msg) => {
    console.log('接收到文件消息：', msg);
    // 广播文件消息
    io.to(msg.channel).emit('fileMessage', msg);
  });

  socket.on('disconnect', () => {
    console.log('客户端断开连接');
  });
});

// 静态文件 fallback 配置
app.get('*', (req, res) => {
  res.sendFile(path.join(buildDir, 'index.html'));
});

// 启动服务器
server.listen(443, () => {
  console.log('服务器运行在 https://chat.777cloud.life');
});
EOF

# 6. 安装前端依赖并构建项目
echo "6. 安装前端依赖并构建项目..."
cd "$FRONTEND_DIR" || exit
npm install || { echo '前端依赖安装失败'; exit 1; }
npm run build || { echo '前端构建失败'; exit 1; }

# 7. 安装后端依赖并启动应用
echo "7. 安装后端依赖..."
cd "$BACKEND_DIR" || exit
npm install || { echo '后端依赖安装失败'; exit 1; }

echo "8. 启动后端应用..."
pm2 start "$BACKEND_DIR/app.js" --name "Pigeon Nest-backend"

# 8. 配置 Nginx
echo "9. 配置 Nginx..."
sudo cp "$PROJECT_ROOT/nginx/your-app.conf" /etc/nginx/sites-available/your-app.conf
sudo ln -s /etc/nginx/sites-available/your-app.conf /etc/nginx/sites-enabled/

# 9. 重启 Nginx
echo "10. 重启 Nginx..."
sudo nginx -t && sudo systemctl restart nginx

# 10. 配置 SSL 证书
echo "11. 配置 SSL 证书..."
sudo certbot --nginx -d $DOMAIN

# 11. 配置自动更新证书
echo "12. 配置证书自动更新..."
(crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet && systemctl reload nginx") | crontab -

# 结束
echo "Pigeon Nest部署完成，访问您的网站: https://$DOMAIN"
