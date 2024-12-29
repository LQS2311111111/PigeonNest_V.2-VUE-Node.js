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
    <!-- 频道号输入页 -->
    <div v-if="!isChannelValid" class="key-container">
      <input
        v-model="channel"
        type="text"
        class="key-input"
        placeholder="请输入频道号"
      />
      <button @click="joinChannel" class="key-button">加入频道</button>
      <div v-if="channelError" class="error-message">请输入有效的频道号。</div>
    </div>

    <!-- 聊天页面 -->
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
            <span v-if="msg.type === 'file'">
              <img v-if="msg.fileUrl" :src="msg.fileUrl" alt="file preview" class="file-preview"/>
              <a v-if="!msg.fileUrl" :href="msg.fileUrl" target="_blank">{{ msg.fileName }}</a>
            </span>
          </div>
        </div>
      </div>

      <div class="input-container">
        <!-- GitHub 图标按钮 -->
        <a href="https://github.com/LQS2311111111/chat-app-VUE-Node.js-.git" target="_blank" class="github-button">
          <i class="fab fa-github"></i>
        </a>

        <!-- 输入框区域 -->
        <input
          v-model="newMessage"
          placeholder="输入消息..."
          @keyup.enter="sendMessage"
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
          style="display: none;"/>
      </div>
    </div>
  </div>
</template>

<script>
import { io } from "socket.io-client";

// 在需要使用 FontAwesome 的 Vue 组件中引入
import '@fortawesome/fontawesome-free/css/all.min.css';

export default {
  data() {
    return {
      channel: "", // 用户输入的频道号
      isChannelValid: false, // 频道号验证状态
      channelError: false, // 错误提示
      newMessage: "", // 用户输入的文本消息
      messages: [], // 消息列表
      socket: null, // WebSocket 连接实例
      selectedFile: null, // 选中的文件
    };
  },
  methods: {
    // 加入频道
    joinChannel() {
      if (!this.channel.trim()) {
        this.channelError = true;
        alert("频道号不能为空！");
        return;
      }

      // 发送加入频道事件
      this.socket.emit("joinChannel", this.channel);
      console.log(`已加入频道: ${this.channel}`);
      
      // 更新状态
      this.isChannelValid = true;
      this.channelError = false; // 清除错误提示

      // 监听频道消息
      this.socket.on("message", (msg) => {
        if (msg.channel === this.channel && !this.messages.some(m => m.id === msg.id)) {
          console.log("接收到消息:", msg);
          this.messages.push(msg); // 添加到消息列表
          this.scheduleMessageDeletion(msg); // 设置消息过期时间
        }
      });

      // 监听文件消息
      this.socket.on("fileMessage", (msg) => {
        if (msg.channel === this.channel && !this.messages.some(m => m.id === msg.id)) {
          console.log("接收到文件消息:", msg);
          this.messages.push(msg); // 添加到消息列表
          this.scheduleMessageDeletion(msg); // 设置消息过期时间
        }
      });
    },

    // 发送文本或文件消息
    sendMessage() {
      if (!this.newMessage.trim() && !this.selectedFile) return;

      const msg = {
        id: Date.now(), // 添加唯一id，避免重复
        text: this.newMessage,
        sender: "self",
        type: this.selectedFile ? "file" : "text",
        fileName: this.selectedFile ? this.selectedFile.name : null,
        fileUrl: this.selectedFile ? URL.createObjectURL(this.selectedFile) : null,
        channel: this.channel, // 所属频道号
        expirationTime: Date.now() + 30000, // 设置消息过期时间（30秒）
      };

      this.messages.push(msg); // 仅在消息发送成功后添加到本地
      this.socket.emit(this.selectedFile ? "fileMessage" : "message", msg); // 发送消息
      console.log("已发送消息:", msg);
      this.newMessage = ""; // 清空输入框
      this.selectedFile = null; // 清空选中文件

      // 设置定时删除自己发送的消息
      this.scheduleMessageDeletion(msg);
    },

    // 定时删除消息
    scheduleMessageDeletion(msg) {
      setTimeout(() => {
        this.messages = this.messages.filter(m => m.id !== msg.id); // 删除该消息
      }, msg.expirationTime - Date.now()); // 根据过期时间来删除消息
    },

    // 触发文件上传逻辑
    triggerFileUpload() {
      this.$refs.fileInput.click();
    },

    // 处理文件上传
    handleFileUpload(event) {
      const file = event.target.files[0];
      if (!file) return;

      const allowedTypes = ["image/jpeg", "image/png", "application/pdf"];
      const maxSizeMB = 5;

      if (!allowedTypes.includes(file.type)) {
        alert("仅支持上传图片或PDF文件！");
        this.$refs.fileInput.value = ""; // 清空选择的文件
        return;
      }

      if (file.size > maxSizeMB * 1024 * 1024) {
        alert(`文件大小不能超过 ${maxSizeMB} MB！`);
        this.$refs.fileInput.value = "";
        return;
      }

      const msg = {
        id: Date.now(), // 添加唯一id，避免重复
        sender: "self",
        type: "file",
        fileName: file.name,
        fileUrl: URL.createObjectURL(file),
        channel: this.channel,
        expirationTime: Date.now() + 30000, // 设置消息过期时间（30秒）
      };

      this.messages.push(msg);
      this.socket.emit("fileMessage", msg);
      console.log("已发送文件消息:", msg);
      this.$refs.fileInput.value = "";
      this.selectedFile = null;

      // 设置定时删除自己发送的文件消息
      this.scheduleMessageDeletion(msg);
    },
  },

  mounted() {
    // WebSocket连接和自动重连
    this.socket = io("https://chat.777cloud.life", {
      reconnection: true,
      reconnectionAttempts: 5,
      reconnectionDelay: 1000,
    });

    this.socket.on("connect", () => {
      console.log("WebSocket 连接成功，客户端 ID:", this.socket.id);
    });
  },

  beforeDestroy() {
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
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
  max-width: 70%;
  padding: 12px 15px;
  border-radius: 15px;
  word-wrap: break-word;
  word-break: break-word;
  display: block;
  margin-bottom: 10px;
  background-color: #3b3b47; /* 黑色气泡 */
  color: white;
  align-self: flex-start;
}

/* 发送消息气泡 */
.message.sent {
  background-color: #7a4dff; /* 紫色 */
  color: white;
  align-self: flex-end;
  text-align: left;
}

/* 接收消息气泡 */
.message.received {
  background-color: #3b3b47;
  color: white;
  align-self: flex-start;
  text-align: left;
}

/* 消息发送者的名字 */
.sender-name {
  font-weight: bold;
  font-size: 14px;
  margin-bottom: 5px;
  color: #c9a0ff; /* 紫色发送者名字 */
}

/* 消息内容 */
.message-content {
  font-size: 16px;
  line-height: 1.4;
}

/* 输入框区域 */
.input-container {
  display: flex;
  padding: 15px;
  background-color: #2c2a3c; /* 深紫色 */
  position: sticky;
  bottom: 0;
  border-top: 1px solid #444;
}

/* 输入框 */
.input-box {
  flex: 1;
  padding: 12px 15px;
  border-radius: 20px;
  border: 1px solid #ccc;
  margin-right: 10px;
  font-size: 16px;
}

/* 按钮样式 */
.send-button {
  padding: 12px 20px;
  border: none;
  border-radius: 20px;
  background-color: #7a4dff; /* 紫色 */
  color: white;
  font-size: 16px;
  cursor: pointer;
}

.send-button:hover {
  background-color: #5b39b7; /* 深紫色 */
}

/* 上传文件按钮 */
.upload-button {
  padding: 12px 20px;
  background-color: #28a745; /* 绿色 */
  color: white;
  border: none;
  border-radius: 20px;
  cursor: pointer;
  margin-left: 10px;
}

.upload-button:hover {
  background-color: #218838; /* 深绿色 */
}

.file-input {
  display: none;
}

/* 给 GitHub 图标设置样式 */
.input-container i {
  font-size: 32px; /* 更大的图标 */
  color: white;
  margin-right: 10px;
}

.input-container i:hover {
  color: #7a4dff; /* 鼠标悬停时变色 */
}

/* 文件预览样式 */
.file-preview {
  border: 2px solid #444;
  border-radius: 10px;
  max-width: 100%;
  height: auto;
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
const express = require("express");
const http = require("http");
const { Server } = require("socket.io");

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(express.json());

// 日志记录
const log = (message) => console.log(`[LOG] ${new Date().toISOString()}: ${message}`);

// 频道号格式验证函数
const isValidChannel = (channel) => {
  const channelRegex = /^[a-zA-Z0-9_-]{3,20}$/; // 频道号必须是3-20个字符，且只能包含字母、数字、下划线和短横线
  return channelRegex.test(channel);
};

io.on("connection", (socket) => {
  log(`用户已连接 ${socket.id}`);

  // 加入频道
  socket.on("joinChannel", (channel) => {
    if (!channel || !isValidChannel(channel)) {
      socket.emit("error", { message: "频道号无效或格式错误" });
      return;
    }
    socket.join(channel);
    log(`用户 ${socket.id} 加入频道 ${channel}`);
  });

  // 接收普通消息并广播给对应频道
  socket.on("message", (data) => {
    if (!data.channel || !isValidChannel(data.channel) || !data.text || typeof data.text !== "string") {
      log("收到无效消息，未发送");
      socket.emit("error", { message: "无效消息，无法发送" });
      return;
    }
    log(`收到消息发送至频道 ${data.channel}:`, data);
    io.to(data.channel).emit("message", { ...data, id: Date.now() }); // 广播给对应频道
  });

  // 接收文件消息并广播给对应频道
  socket.on("fileMessage", (data) => {
    if (!data.channel || !isValidChannel(data.channel) || !data.fileName || !data.fileUrl) {
      log("收到无效文件消息，未发送");
      socket.emit("error", { message: "无效文件消息，无法发送" });
      return;
    }
    log(`收到文件消息发送至频道 ${data.channel}:`, data);
    io.to(data.channel).emit("fileMessage", { ...data, id: Date.now() }); // 广播文件消息
  });

  socket.on("disconnect", () => {
    log(`用户已断开连接 ${socket.id}`);
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  log(`服务器运行在端口 ${PORT}`);
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
