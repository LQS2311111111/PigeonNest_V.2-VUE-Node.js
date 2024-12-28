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
    "build": "vue-cli-service build"
  },
  "dependencies": {
    "vue": "^3.0.0",
    "socket.io-client": "^4.0.0"
  },
  "devDependencies": {
    "@vue/cli-service": "^5.0.0"
  }
}
EOF

mkdir -p "$FRONTEND_DIR/src"

cat > "$FRONTEND_DIR/src/main.js" <<EOF
import { createApp } from 'vue';
import App from './App.vue';
createApp(App).mount('#app');
EOF

cat > "$FRONTEND_DIR/src/App.vue" <<EOF
<template>
  <div id="app" class="chat-container">
    <!-- 密钥输入页 -->
    <div v-if="!isKeyValid" class="key-container">
      <input
        v-model="key"
        type="text"
        class="key-input"
        placeholder="请输入密钥"
      />
      <button @click="validateKey" class="key-button">验证密钥</button>
      <div v-if="keyError" class="error-message">密钥错误，请重试。</div>
    </div>

    <!-- 聊天页面 -->
    <div v-else>
      <div class="header">去中心化即时通讯</div>
      <div class="messages">
        <div
          v-for="(msg, index) in messages"
          :key="index"
          class="message"
          :class="{ 'sent': msg.sender === 'self', 'received': msg.sender !== 'self' }"
        >
          <div class="sender-name" v-if="msg.senderName">{{ msg.senderName }}</div>
          <div class="message-content">
            <span v-if="msg.type === 'text'">{{ msg.text }}</span>
            <span v-if="msg.type === 'file'">
              <a :href="msg.fileUrl" target="_blank">{{ msg.fileName }}</a>
            </span>
          </div>
          <div class="timestamp">{{ new Date(msg.timestamp).toLocaleString() }}</div>
        </div>
      </div>

      <div class="input-container">
        <input
          v-model="newMessage"
          placeholder="输入消息..."
          @input="checkUploadFileCommand"
          class="input-box"
        />
        <button @click="sendMessage" class="send-button">发送</button>
        <button @click="triggerFileUpload" class="upload-button">上传文件</button>
        <input
          type="file"
          id="file-upload"
          ref="fileInput"
          @change="handleFileUpload"
          class="file-input"
          style="display: none;"
        />
      </div>

      <!-- GitHub 项目跳转按钮 -->
      <div class="github-link">
        <button @click="https://github.com/LQS2311111111/chat-app-VUE-Node.js-.git" class="github-button">查看我的 GitHub 项目</button>
      </div>
    </div>
  </div>
</template>


<script>
import { io } from "socket.io-client";

export default {
  data() {
    return {
      key: "", // 用户输入的密钥
      isKeyValid: false, // 密钥验证状态
      keyError: false, // 错误提示
      newMessage: "", // 用户输入的文本消息
      messages: [], // 消息列表
      socket: null, // WebSocket 连接实例
      selectedFile: null, // 选中的文件
    };
  },
  methods: {
    // 密钥哈希验证
    async hashKey(key) {
      const encoder = new TextEncoder();
      const data = encoder.encode(key);
      return crypto.subtle.digest("SHA-256", data).then((hashBuffer) => {
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        return hashArray.map(byte => byte.toString(16).padStart(2, '0')).join('');
      });
    },

    // 验证密钥
    async validateKey() {
      try {
        const hashedKey = await this.hashKey(this.key);
        
        // 与后端的密钥哈希值进行比对
        const response = await fetch('https://$DOMAIN/validateKey', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ key: hashedKey })
        });

        const data = await response.json();
        
        if (data.success) {
          this.isKeyValid = true; // 密钥验证成功
        } else {
          this.keyError = true; // 密钥错误
        }
      } catch (error) {
        console.error("验证失败", error);
        this.keyError = true;
      }
    },

    // 检查输入是否包含"上传文件"字眼
    checkUploadFileCommand() {
      if (/\b上传文件\b/i.test(this.newMessage.trim())) {
        setTimeout(() => {
          this.triggerFileUpload();
          this.newMessage = "";
        }, 100);
      }
    },

    sendMessage() {
      if (!this.newMessage.trim() && !this.selectedFile) return;

      const msg = {
        text: this.newMessage,
        sender: "self",
        timestamp: new Date(),
        type: this.selectedFile ? "file" : "text",
        fileName: this.selectedFile ? this.selectedFile.name : null,
        fileUrl: this.selectedFile ? URL.createObjectURL(this.selectedFile) : null,
      };

      this.messages.push(msg);

      if (this.selectedFile) {
        this.socket.emit("fileMessage", msg);
      } else {
        this.socket.emit("message", msg);
      }

      this.newMessage = "";
      this.selectedFile = null;
    },

    triggerFileUpload() {
      if (this.$refs.fileInput) {
        this.$refs.fileInput.click();
      } else {
        console.error('未找到文件上传输入框');
      }
    },

    handleFileUpload(event) {
      const file = event.target.files[0];
      if (file) {
        const msg = {
          sender: "self",
          timestamp: new Date(),
          type: "file",
          fileName: file.name,
          fileUrl: URL.createObjectURL(file),
        };

        this.messages.push(msg);
        this.socket.emit("fileMessage", msg);
        this.selectedFile = null;
      }
    },

    // 跳转到GitHub项目
    goToGitHub() {
      window.location.href = "https://github.com/LQS2311111111/chat-app-VUE-Node.js-.git"; // 请替换为你的GitHub项目链接
    }
  },

  mounted() {
    this.socket = io("https://chat.777cloud.life", {
      path: "/socket.io/",
      transports: ["websocket", "polling"],
    });

    this.socket.on("message", (msg) => {
      msg.senderName = msg.senderName || "未知用户";
      this.messages.push(msg);
    });

    this.socket.on("fileMessage", (msg) => {
      msg.senderName = msg.senderName || "未知用户";
      this.messages.push(msg);
    });

    this.socket.on("connect_error", () => {
      alert("连接失败，请稍后再试...");
    });
  },
};
</script>


<style scoped>
/* 样式：全局容器 */
.chat-container {
  font-family: Arial, sans-serif;
  display: flex;
  flex-direction: column;
  height: 100vh;
  background: #f5f5f5;
  color: #333;
}

/* 密钥输入页面 */
.key-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
  flex-direction: column;
}

.key-input {
  padding: 10px;
  font-size: 16px;
  border-radius: 5px;
  margin-right: 10px;
}

.key-button {
  padding: 10px 20px;
  background-color: #4caf50;
  color: white;
  border: none;
  border-radius: 5px;
  cursor: pointer;
}

.key-button:hover {
  background-color: #45a049;
}

.error-message {
  color: red;
  margin-top: 10px;
}

/* 头部样式 */
.header {
  padding: 20px;
  background: #000;
  color: #fff;
  text-align: center;
  font-size: 20px;
}

/* 消息列表 */
.messages {
  flex: 1;
  overflow-y: auto;
  padding: 20px;
  background: #fff;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

/* 消息气泡 */
.message {
  max-width: 70%;
  padding: 12px 15px;
  border-radius: 15px;
  word-wrap: break-word;
  word-break: break-word;
  display: block;
  margin-bottom: 10px;
  background-color: #f1f0f0;
  color: #333;
  align-self: flex-start;
}

/* 发送消息气泡 */
.message.sent {
  background: #000;
  color: #fff;
  align-self: flex-end;
  text-align: left;
}

/* 接收消息气泡 */
.message.received {
  background: #f1f0f0;
  color: #333;
  align-self: flex-start;
  text-align: left;
}

/* 消息发送者的名字 */
.sender-name {
  font-weight: bold;
  font-size: 14px;
  margin-bottom: 5px;
  color: #007BFF;
}

/* 消息内容 */
.message-content {
  font-size: 16px;
}

/* 时间戳 */
.timestamp {
  font-size: 12px;
  color: #007BFF;
  margin-top: 5px;
  text-align: right;
  width: 100%;
  font-style: italic;
}

/* 输入框区域 */
.input-container {
  display: flex;
  padding: 10px;
  background: #000;
  position: sticky;
  bottom: 0;
}

/* 输入框 */
.input-box {
  flex: 1;
  padding: 10px;
  border: none;
  border-radius: 15px;
  margin-right: 10px;
  font-size: 16px;
}

/* 按钮样式 */
.send-button {
  padding: 10px 20px;
  border: none;
  border-radius: 15px;
  background: #fff;
  color: #000;
  font-size: 16px;
  cursor: pointer;
}

.send-button:hover {
  background: #000;
  color: #fff;
}

/* 上传文件按钮 */
.upload-button {
  padding: 10px 20px;
  border: none;
  border-radius: 15px;
  background: #fff;
  color: #000;
  font-size: 16px;
  cursor: pointer;
  margin-left: 10px;
}

.upload-button:hover {
  background: #000;
  color: #fff;
}

/* 隐藏的文件输入框 */
.file-input {
  display: none;
}

/* GitHub按钮样式 */
.github-link {
  margin-top: 20px;
  text-align: center;
}

.github-button {
  padding: 10px 20px;
  background-color: #333;
  color: #fff;
  font-size: 16px;
  border: none;
  border-radius: 5px;
  cursor: pointer;
}

.github-button:hover {
  background-color: #007BFF;
}
</style>
EOF

cd "$FRONTEND_DIR"
npm install
npm run build
sudo cp -r dist/* /var/www/html/

# 6. 写入后端代码
echo "6. 写入后端代码..."
cat > "$BACKEND_DIR/package.json" <<EOF
{
  "name": "chat-app-backend",
  "version": "1.0.0",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.17.1",
    "socket.io": "^4.0.0"
  }
}
EOF

cat > "$BACKEND_DIR/app.js" <<EOF
const http = require('http');
const express = require('express');
const app = express();
const server = http.createServer(app);
const fs = require('fs');
const path = require('path');
const crypto = require('crypto'); // 引入 crypto 模块
const logStream = fs.createWriteStream(path.join(__dirname, 'chat-app-backend.log'), { flags: 'a' });

console.log = (...args) => {
  logStream.write(args.join(' ') + '\n');
  process.stdout.write(args.join(' ') + '\n');
};

console.error = (...args) => {
  logStream.write(args.join(' ') + '\n');
  process.stderr.write(args.join(' ') + '\n');
};

// 用于存储在线用户列表，便于后续管理
let onlineUsers = {};
const io = require('socket.io')(server, {
  path: '/socket.io/',
  transports: ['websocket', 'polling'],
  cors: {
    origin: "https://chat.777cloud.life",
    methods: ["GET", "POST"]
  }
});

//// 固定的密钥及其哈希值
//const validKeyHash = "a8f5c88d2a1f8a5c5f88f7f8b0f4c7b74bb8ef8b6d5f02e9d09e5477b963a350"; // 使用预先存储的密钥的哈希值

// 处理连接
io.on('connection', (socket) => {
  console.log(`a user connected: ${socket.id}`);
  let userName = `User_${socket.id.substring(0, 6)}`; // 使用 socket.id 的前6位作为用户名的一部分
  onlineUsers[socket.id] = userName;

  socket.on('keyCheck', (key) => {
    // 对用户传来的密钥进行哈希处理
    const hashedKey = crypto.createHash('sha256').update(key).digest('hex');

    // 如果密钥哈希正确，加入主频道，否则加入其他频道
    if (hashedKey === validKeyHash) {
      socket.join('main'); // 主频道
    } else {
      socket.join('other'); // 其他频道
    }

    io.emit('userConnected', { userName, socketId: socket.id });
  });

  // 监听客户端发送的消息
  socket.on('message', (msg) => {
    io.emit('message', {
      ...msg,
      senderName: userName,
      senderId: socket.id,
      timestamp: new Date(),
    });
  });

  socket.on('fileMessage', (msg) => {
    io.emit('fileMessage', {
      ...msg,
      senderName: userName,
      senderId: socket.id,
      timestamp: new Date(),
    });
  });

  socket.on('disconnect', () => {
    console.log(`user disconnected: ${socket.id}`);
    delete onlineUsers[socket.id];
    io.emit('userDisconnected', { userName, socketId: socket.id });
  });
});
// 密钥验证路由
app.post("/validateKey", express.json(), (req, res) => {
  const { key } = req.body;

  // 哈希密钥验证
  const hash = crypto.createHash("sha256").update(key).digest("hex");

  if (hash === validHashedKey) {
    res.json({ success: true, message: "密钥验证成功" });
  } else {
    res.status(400).json({ success: false, message: "密钥验证失败" });
  }
});
app.post('/validateKey', express.json(), (req, res) => {
  const { key } = req.body;
  const validKeyHash = '正确的哈希值';  // 替换为实际的正确哈希值

  // 检查哈希值是否匹配
  if (key === validKeyHash) {
    return res.json({ success: true });
  } else {
    return res.status(400).json({ success: false });
  }
});

server.listen(3000, () => {
  console.log('Server is running on http://127.0.0.1:3000');
});
EOF

cd "$BACKEND_DIR"
npm install
pm2 start app.js --name chat-backend
pm2 save

# 7. 配置 Nginx
echo "7. 配置 Nginx..."
sudo bash -c "cat > /etc/nginx/sites-available/chat-app" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate $SSL_CERT;
    ssl_certificate_key $SSL_KEY;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/chat-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# 8. 配置并申请 SSL 证书
echo "8. 请输入您的域名（例如: example.com）:"
read DOMAIN

echo "正在申请 SSL 证书..."
sudo certbot --nginx -d $DOMAIN
sudo systemctl reload nginx

# 自动更新证书
echo "9. 配置自动更新任务..."
sudo bash -c "echo '0 3 * * * certbot renew --quiet && systemctl reload nginx' >> /etc/crontab"

# 完成
echo "========== 部署完成 =========="
echo "访问: https://$DOMAIN"
