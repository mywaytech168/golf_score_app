import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'
import { fileURLToPath } from 'url'

// ---------- 方法區 ----------
// 匯出 Vite 設定，啟用 Vue 插件並使用相對路徑
const __dirname = path.dirname(fileURLToPath(import.meta.url))
export default defineConfig({
  plugins: [vue()],
  base: './',
  build: {
    // 將打包結果輸出至後端 server 的 wwwroot/dist 以方便部署
    outDir: path.resolve(__dirname, '../server/wwwroot/dist'),
    emptyOutDir: true
  }
})
