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

      // 设置定时删除文件消息
      this.scheduleMessageDeletion(msg);
    }
  },

  created() {
    this.socket = io("https://your-server-domain"); // 替换为你的后端域名
  }
};
</script>

<style scoped>
/* 样式略 */
</style>
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
pm2 start "$BACKEND_DIR/server.js" --name "chat-app-backend"

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
