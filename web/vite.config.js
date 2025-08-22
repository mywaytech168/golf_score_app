import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// ---------- 方法區 ----------
// 匯出 Vite 設定，啟用 Vue 插件並使用相對路徑
export default defineConfig({
  plugins: [vue()],
  base: './'
})
