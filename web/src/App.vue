<script setup>
// ---------- API 呼叫區 ----------
// 此元件不涉及外部 API

// ---------- 方法區 ----------
import { ref, onMounted } from 'vue'

// 可用鏡頭清單
const videoDevices = ref([])
// 選擇中的鏡頭 ID
const selectedDeviceId = ref('')

// 鏡頭畫面元素
const videoEl = ref(null)
// 媒體串流
const mediaStream = ref(null)

// 錄影相關狀態
const mediaRecorder = ref(null)
const recordedChunks = ref([])
const downloadUrl = ref('')
const isRecording = ref(false)

// 取得可用鏡頭清單
async function loadDevices() {
  // 呼叫硬體取得所有媒體裝置
  const devices = await navigator.mediaDevices.enumerateDevices()
  videoDevices.value = devices.filter(d => d.kind === 'videoinput')
  if (videoDevices.value.length > 0) {
    selectedDeviceId.value = videoDevices.value[0].deviceId
  }
}

// 開啟鏡頭
async function startCamera() {
  if (mediaStream.value) {
    mediaStream.value.getTracks().forEach(t => t.stop())
  }
  mediaStream.value = await navigator.mediaDevices.getUserMedia({
    video: selectedDeviceId.value ? { deviceId: { exact: selectedDeviceId.value } } : true
  })
  if (videoEl.value) {
    videoEl.value.srcObject = mediaStream.value
    await videoEl.value.play()
  }
}

// 切換鏡頭
async function switchCamera(id) {
  selectedDeviceId.value = id
  await startCamera()
}

// 開始錄影
function startRecording() {
  if (!mediaStream.value) return
  recordedChunks.value = []
  mediaRecorder.value = new MediaRecorder(mediaStream.value)
  mediaRecorder.value.ondataavailable = e => recordedChunks.value.push(e.data)
  mediaRecorder.value.onstop = handleStop
  mediaRecorder.value.start()
  isRecording.value = true
}

// 停止錄影
function stopRecording() {
  if (mediaRecorder.value && isRecording.value) {
    mediaRecorder.value.stop()
  }
}

// 錄影結束後處理檔案
function handleStop() {
  isRecording.value = false
  const blob = new Blob(recordedChunks.value, { type: 'video/webm' })
  downloadUrl.value = URL.createObjectURL(blob)
}

// 下載影片
function downloadVideo() {
  if (!downloadUrl.value) return
  const a = document.createElement('a')
  a.href = downloadUrl.value
  a.download = 'record.webm'
  a.click()
  URL.revokeObjectURL(downloadUrl.value)
  downloadUrl.value = ''
}

// ---------- 生命週期 ----------
onMounted(async () => {
  await loadDevices()
  await startCamera()
})
</script>

<template>
  <el-container class="app-container">
    <el-main>
      <h1>鏡頭錄影範例</h1>

      <!-- 鏡頭選擇 -->
      <el-select v-model="selectedDeviceId" placeholder="選擇鏡頭" @change="switchCamera">
        <el-option
          v-for="device in videoDevices"
          :key="device.deviceId"
          :label="device.label || `鏡頭 ${device.deviceId}`"
          :value="device.deviceId"
        />
      </el-select>

      <!-- 鏡頭畫面 -->
      <video ref="videoEl" class="preview" autoplay muted></video>

      <!-- 錄影與下載按鈕 -->
      <div class="btn-group">
        <el-button type="primary" @click="isRecording ? stopRecording() : startRecording()">
          {{ isRecording ? '停止錄影' : '開始錄影' }}
        </el-button>
        <el-button type="success" :disabled="!downloadUrl" @click="downloadVideo">
          下載影片
        </el-button>
      </div>
    </el-main>
  </el-container>
</template>

<style scoped>
.app-container {
  padding: 40px;
}

.preview {
  width: 100%;
  max-width: 400px;
  margin-top: 20px;
  background: #000;
}

.btn-group {
  margin-top: 20px;
  display: flex;
  gap: 10px;
}
</style>
