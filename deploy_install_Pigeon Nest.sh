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
        <a href="https://github.com/LQS2311111111/PigeonNest_V.2-VUE-Node.js.git" target="_blank" class="github-button">
          <i class="fab fa-github"></i>
        </a>

        <!-- 输入框区域 -->
        <input
          v-model="newMessage"
          placeholder="输入消息..."
          @keyup.enter="sendMessage"
          class="input-box"
        />
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
    </div>
  </div>
</template>

<script>
import { io } from "socket.io-client";
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
      this.channelError = false;
    
      // 清除所有现有的消息监听，确保每次只有一个消息处理器
      this.socket.removeAllListeners("message");
      this.socket.removeAllListeners("fileMessage");
    
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
        id: Date.now(),
        text: this.newMessage,
        sender: "self",
        type: this.selectedFile ? "file" : "text",
        fileName: this.selectedFile ? this.selectedFile.name : null,
        fileUrl: this.selectedFile ? URL.createObjectURL(this.selectedFile) : null,
        channel: this.channel,
        expirationTime: Date.now() + 30000, 
      };

      this.messages.push(msg); // 添加到本地
      this.socket.emit(this.selectedFile ? "fileMessage" : "message", msg); // 发送消息
      console.log("已发送消息:", msg);
      this.newMessage = ""; // 清空输入框
      this.selectedFile = null;

      // 设置定时删除消息
      this.scheduleMessageDeletion(msg);
    },

    // 定时删除消息
    scheduleMessageDeletion(msg) {
      setTimeout(() => {
        this.messages = this.messages.filter(m => m.id !== msg.id);
      }, msg.expirationTime - Date.now());
    },

    // 触发文件上传
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
        this.$refs.fileInput.value = "";
        return;
      }

      if (file.size > maxSizeMB * 1024 * 1024) {
        alert(`文件大小不能超过 ${maxSizeMB} MB！`);
        this.$refs.fileInput.value = "";
        return;
      }

      const msg = {
        id: Date.now(),
        sender: "self",
        type: "file",
        fileName: file.name,
        fileUrl: URL.createObjectURL(file),
        channel: this.channel,
        expirationTime: Date.now() + 30000,
      };

      this.messages.push(msg);
      this.socket.emit("fileMessage", msg);
      console.log("已发送文件消息:", msg);
      this.$refs.fileInput.value = "";
      this.selectedFile = null;

      // 设置定时删除文件消息
      this.scheduleMessageDeletion(msg);
    }
  },

  created() {
    this.socket = io("https://chat.777cloud.life"); // 使用实际的生产域名
  }
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
  border-radius: 50%;
  background-color: #7a4dff;
  color: white;
  border: none;
  cursor: pointer;
}

.send-button:hover, .upload-button:hover {
  background-color: #5b39b7;
}

.github-button {
  position: absolute;
  top: 20px;
  right: 20px;
  color: #fff;
  font-size: 24px;
}
</style>
EOF

echo "创建后端 app.js 文件..."
cat > "$BACKEND_DIR/app.js" <<'EOF'
const express = require("express");
const fileUpload = require("express-fileupload");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { Server } = require("socket.io");
const morgan = require("morgan");

const app = express();
const server = http.createServer(app);
const io = new Server(server);

// 上传文件存储目录
const uploadDir = path.join(__dirname, "uploads");
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir);
}

// 中间件配置
app.use(morgan("dev")); // HTTP 请求日志
app.use(express.static("public")); // 前端静态资源
app.use(
  fileUpload({
    limits: { fileSize: 20 * 1024 * 1024 }, // 最大上传文件大小：20MB
    abortOnLimit: true,
    responseOnLimit: "上传文件大小超出限制！",
  })
);
app.use("/uploads", express.static(uploadDir)); // 提供上传的文件

// 上传文件接口
app.post("/upload", (req, res) => {
  const file = req.files?.file;
  if (!file) {
    return res.status(400).send("没有文件上传");
  }

  // 验证文件类型
  const allowedTypes = ["image/jpeg", "image/png", "application/pdf"];
  if (!allowedTypes.includes(file.mimetype)) {
    return res.status(400).send("只支持 JPEG、PNG 或 PDF 文件");
  }

  // 存储文件
  const timeStamp = Date.now();
  const sanitizedFileName = file.name.replace(/[\s\#]/g, "_"); // 替换文件名中的空格和特殊字符
  const fileName = ${timeStamp}_${sanitizedFileName};
  const filePath = path.join(uploadDir, fileName);

  file.mv(filePath, (err) => {
    if (err) {
      console.error("文件上传错误:", err);
      return res.status(500).send("文件上传失败");
    }
    const fileUrl = /uploads/${fileName};
    res.send({ fileUrl }); // 返回文件地址
  });
});

// WebSocket 处理
io.on("connection", (socket) => {
  console.log("客户端连接成功:", socket.id);

  // 加入频道
  socket.on("joinChannel", (channel) => {
    if (!channel) return;
    socket.join(channel);
    console.log(客户端已加入频道: ${channel});
  });

  // 处理消息
  socket.on("message", (msg) => {
    if (!msg || !msg.channel) return;
    io.to(msg.channel).emit("message", msg); // 广播到指定频道
  });

  // 处理文件消息
  socket.on("fileMessage", (msg) => {
    if (!msg || !msg.channel) return;
    io.to(msg.channel).emit("fileMessage", msg);
  });

  // 客户端断开连接
  socket.on("disconnect", () => {
    console.log("客户端断开连接:", socket.id);
  });
});

// 捕获未处理异常
process.on("uncaughtException", (err) => {
  console.error("未捕获异常:", err);
});

// 启动服务
const port = process.env.PORT || 3000;
server.listen(port, () => {
	console.log(`服务器运行在 http://chat.777cloud.life:${port}`);
}
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
pm2 start "$BACKEND_DIR/app.js" --name "chat-app-backend"

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
echo "部署完成，访问您的网站: https://$DOMAIN"
