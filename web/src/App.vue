<script setup>
// ---------- API 呼叫區 ----------
// 無需呼叫外部 API

// ---------- 方法區 ----------
import { ref } from 'vue'

// 計數狀態
const count = ref(0)

// 點擊按鈕時增加計數
function increment() {
  count.value++
}

// ---------- 生命週期 ----------
// 此元件目前無額外生命週期需求
</script>

<template>
  <el-container class="app-container">
    <el-main>
      <h1>Vite + Vue + Element Plus</h1>
      <!-- Element Plus 按鈕，點擊可遞增計數 -->
      <el-button type="primary" @click="increment">
        計數：{{ count }}
      </el-button>
    </el-main>
  </el-container>
</template>

<style scoped>
.app-container {
  padding: 40px;
}
</style>
