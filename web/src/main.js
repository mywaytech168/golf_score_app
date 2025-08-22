// ---------- API 呼叫區 ----------
// 此示範專案暫無 API 呼叫

// ---------- 方法區 ----------
// 建立並掛載 Vue 應用
import { createApp } from 'vue'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import App from './App.vue'

// ---------- 生命週期 ----------
// 建立應用並註冊 Element Plus，最後掛載到頁面
createApp(App).use(ElementPlus).mount('#app')
