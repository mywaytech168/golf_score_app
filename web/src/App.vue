<template>
  <div class="app-wrapper">
    <LoginPanel v-if="!isAuthenticated" @login-success="handleLoginSuccess" />

    <section v-else class="app-placeholder">
      <el-result icon="success" title="TekSwing 應用主畫面" sub-title="示意畫面：登入成功後導向錄影系統">
        <template #extra>
          <el-card class="app-card" shadow="hover">
            <p class="app-greeting">目前以 {{ activeAccount }} 登入</p>
            <p class="app-description">稍後可串接實際的揮桿錄影與分析模組</p>
            <el-button type="primary" @click="handleLogout">返回登入頁</el-button>
          </el-card>
        </template>
      </el-result>
    </section>
  </div>
</template>

<script setup lang="ts">
// ---------- API 呼叫區 ----------
// 靜態示範頁面暫無 API 呼叫

// ---------- 方法區 ----------
import { ref } from 'vue'
import { ElMessage } from 'element-plus'
import LoginPanel from './components/LoginPanel.vue'

// 控制是否已登入，預設顯示登入畫面，避免啟動後直接進入內部功能
const isAuthenticated = ref(false)

// 紀錄登入帳號，便於登入後展示歡迎訊息
const activeAccount = ref('')

// 當子元件完成登入檢核後切換至主畫面
function handleLoginSuccess(email: string) {
  activeAccount.value = email
  isAuthenticated.value = true
  ElMessage.success(`歡迎回來，${email}`)
}

// 提供示意的登出行為，讓測試者能回到登入畫面
function handleLogout() {
  isAuthenticated.value = false
  activeAccount.value = ''
  ElMessage.info('已登出 TekSwing，請重新登入')
}

// ---------- 生命週期 ----------
// 本頁面主要透過狀態切換，不需額外生命週期操作
</script>

<style scoped>
.app-wrapper {
  min-height: 100vh;
}

.app-placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  background: linear-gradient(180deg, #f5fbff 0%, #ffffff 100%);
  padding: 48px 24px;
}

.app-card {
  max-width: 360px;
  text-align: center;
  border-radius: 24px;
  border: 1px solid rgba(20, 74, 46, 0.12);
}

.app-greeting {
  margin: 0 0 12px;
  font-size: 20px;
  font-weight: 700;
  color: #1a3a2b;
}

.app-description {
  margin: 0 0 24px;
  font-size: 14px;
  color: #4b5d52;
}
</style>
