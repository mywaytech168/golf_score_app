<template>
  <div class="login-layout">
    <section class="visual-panel">
      <div class="visual-content">
        <h1 class="visual-title">TekSwing</h1>
        <p class="visual-caption">"Master Your Swing"</p>
        <p class="visual-caption secondary">Unlock Your Potential."</p>
        <div class="visual-illustration">
          <!-- 採用提供的品牌插畫，強化與設計稿一致的視覺呈現 -->
          <img class="visual-image" :src="loginVisual" alt="TekSwing 品牌揮桿插畫" />
        </div>
      </div>
    </section>

    <section class="form-panel">
      <el-card shadow="never" class="login-card">
        <div class="card-header">
          <div class="card-logo">
            <div class="logo-circle">
              <el-icon :size="24">
                <Flag />
              </el-icon>
            </div>
            <div>
              <p class="card-title">歡迎回到 TekSwing</p>
              <p class="card-subtitle">登入以同步您的揮桿數據</p>
            </div>
          </div>
        </div>

        <el-form class="login-form" :model="loginForm" @submit.prevent="submitLogin">
          <el-form-item>
            <el-input v-model="loginForm.email" placeholder="電子郵件" size="large">
              <template #prefix>
                <el-icon><User /></el-icon>
              </template>
            </el-input>
          </el-form-item>
          <el-form-item>
            <el-input
              v-model="loginForm.password"
              placeholder="密碼"
              size="large"
              type="password"
              show-password
            >
              <template #prefix>
                <el-icon><Lock /></el-icon>
              </template>
            </el-input>
          </el-form-item>
          <el-button type="primary" class="login-button" size="large" @click="submitLogin">
            登入 TekSwing
          </el-button>
        </el-form>

        <div class="social-login">
          <p class="social-label">或使用社群帳號登入</p>
          <div class="social-actions">
            <el-button class="google-button" size="large" @click="handleGoogleLogin">
              <span class="social-icon g-icon">G</span>
              使用 Google 登入
            </el-button>
            <el-button class="apple-button" size="large" @click="handleAppleLogin">
              <span class="social-icon"></span>
              使用 Apple 登入
            </el-button>
          </div>
        </div>

        <div class="helper-links">
          <el-link type="primary" @click="handleForgot">忘記密碼？</el-link>
          <el-link @click="handleContact">聯絡客服</el-link>
        </div>
      </el-card>
    </section>
  </div>
</template>

<script setup lang="ts">
// ---------- API 呼叫區 ----------
// 目前僅示範表單互動流程，尚未整合後端登入 API

// ---------- 方法區 ----------
import { reactive } from 'vue'
import { ElMessage } from 'element-plus'
import { Flag, Lock, User } from '@element-plus/icons-vue'
import loginVisual from '../assets/login-visual.svg'

// 對外發出登入成功事件，供外層控制流程
const emit = defineEmits<{
  (event: 'login-success', email: string): void
}>()

// 使用 reactive 建立登入表單資料，方便雙向綁定與後續擴充欄位
const loginForm = reactive({
  email: '',
  password: ''
})

// 基礎登入送出流程：檢查必填欄位並回報結果
function submitLogin() {
  if (!loginForm.email || !loginForm.password) {
    ElMessage.warning('請完整輸入電子郵件與密碼')
    return
  }

  // 登入成功由外層決定後續頁面顯示
  emit('login-success', loginForm.email)
}

// 透過社群登入時，提示正在進行的第三方驗證流程
function handleGoogleLogin() {
  ElMessage.info('即將透過 Google 驗證登入')
}

// Apple 登入流程同樣可在此銜接實際 OAuth，暫以提示示範
function handleAppleLogin() {
  ElMessage.info('即將透過 Apple ID 驗證登入')
}

// 忘記密碼提示，後續可導向實際重設流程頁面
function handleForgot() {
  ElMessage.info('我們已收到重設密碼需求，請稍候查看信箱')
}

// 聯絡客服入口，提供使用者遇到問題時的指引
function handleContact() {
  ElMessage.info('客服團隊將盡快與您聯繫')
}

// ---------- 生命週期 ----------
// 靜態頁面目前無需額外的生命週期事件
</script>

<style scoped>
.login-layout {
  display: grid;
  grid-template-columns: 1fr 1fr;
  min-height: 100vh;
  background: linear-gradient(180deg, #f5fbff 0%, #ffffff 100%);
}

.visual-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 64px 48px;
  background: linear-gradient(160deg, rgba(70, 195, 154, 0.16), rgba(255, 212, 59, 0.12));
}

.visual-content {
  max-width: 360px;
  text-align: left;
}

.visual-title {
  margin: 0 0 16px;
  font-size: 52px;
  font-weight: 700;
  letter-spacing: 1px;
  background: linear-gradient(120deg, #39a96b 0%, #ffd43b 100%);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.visual-caption {
  margin: 0;
  font-size: 20px;
  font-weight: 600;
  color: #42624c;
}

.visual-caption.secondary {
  margin-top: 6px;
  font-weight: 500;
  color: #5d7362;
}

.visual-illustration {
  margin-top: 48px;
}

.visual-image {
  display: block;
  width: 100%;
  max-width: 320px;
}

.form-panel {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 64px 48px;
}

.login-card {
  width: 420px;
  border-radius: 32px;
  padding: 48px 40px;
  border: 1px solid rgba(20, 74, 46, 0.12);
  box-shadow: 0 28px 60px rgba(20, 74, 46, 0.12);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}

.card-logo {
  display: flex;
  align-items: center;
  gap: 16px;
}

.logo-circle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 48px;
  height: 48px;
  border-radius: 24px;
  background: linear-gradient(135deg, #1f7a4d, #54d18d);
  color: #ffffff;
}

.card-title {
  margin: 0;
  font-size: 22px;
  font-weight: 700;
  color: #1a3a2b;
}

.card-subtitle {
  margin: 4px 0 0;
  font-size: 14px;
  color: #4b5d52;
}

.login-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.login-button {
  width: 100%;
  height: 48px;
  border-radius: 24px;
  font-weight: 600;
  letter-spacing: 1px;
}

.social-login {
  margin-top: 32px;
  text-align: center;
}

.social-label {
  margin-bottom: 16px;
  font-size: 14px;
  color: #6f7c74;
}

.social-actions {
  display: grid;
  gap: 12px;
}

.google-button,
.apple-button {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  width: 100%;
  border-radius: 24px;
  font-weight: 600;
}

.google-button {
  background: #ffffff;
  border: 1px solid rgba(66, 133, 244, 0.3);
  color: #1a3a2b;
}

.apple-button {
  background: #1a1a1a;
  border: 1px solid #000000;
  color: #ffffff;
}

.social-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 20px;
  height: 20px;
  font-size: 16px;
  font-weight: 700;
}

.g-icon {
  color: #1a73e8;
}

.helper-links {
  margin-top: 24px;
  display: flex;
  justify-content: space-between;
}

@media (max-width: 1024px) {
  .login-layout {
    grid-template-columns: 1fr;
  }

  .visual-panel {
    padding-bottom: 24px;
  }

  .form-panel {
    padding-top: 24px;
  }

  .login-card {
    width: 100%;
    max-width: 420px;
  }
}
</style>
