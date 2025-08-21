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

// 使用者選擇的影片格式，預設 webm
const selectedFormat = ref('webm')
// 上一次錄影使用的格式，供單支下載時設定副檔名
const lastFormat = ref('webm')
// 多次錄影設定：錄影次數與每段秒數
const recordTimes = ref(1)
const intervalSec = ref(3)
// 累積所有錄影檔案
const allBlobs = ref([])

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

// 取得當前可用的 MIME 類型，若瀏覽器不支援 mp4 則退回 webm
function getMimeType(format) {
  const type = format === 'mp4' ? 'video/mp4' : 'video/webm'
  return MediaRecorder.isTypeSupported(type) ? type : 'video/webm'
}

// 開始錄影
let currentFormat = 'webm'
function startRecording() {
  if (!mediaStream.value) return
  recordedChunks.value = []
  // 確認瀏覽器支援的格式
  const mimeType = getMimeType(selectedFormat.value)
  currentFormat = mimeType === 'video/mp4' ? 'mp4' : 'webm'
  mediaRecorder.value = new MediaRecorder(mediaStream.value, { mimeType })
  mediaRecorder.value.ondataavailable = e => recordedChunks.value.push(e.data)
  mediaRecorder.value.start()
  isRecording.value = true
}

// 停止錄影，回傳 Promise 以利自動化流程等待
function stopRecording() {
  return new Promise(resolve => {
    if (mediaRecorder.value && isRecording.value) {
      mediaRecorder.value.onstop = () => {
        handleStop()
        resolve()
      }
      mediaRecorder.value.stop()
    } else {
      resolve()
    }
  })
}

// 錄影結束後處理檔案
function handleStop() {
  isRecording.value = false
  const mimeType = currentFormat === 'mp4' ? 'video/mp4' : 'video/webm'
  const blob = new Blob(recordedChunks.value, { type: mimeType })
  downloadUrl.value = URL.createObjectURL(blob)
  lastFormat.value = currentFormat
  allBlobs.value.push({ blob, format: currentFormat })
}

// 下載最新一支影片
function downloadVideo() {
  if (!downloadUrl.value) return
  const a = document.createElement('a')
  a.href = downloadUrl.value
  a.download = `record.${lastFormat.value}`
  a.click()
  URL.revokeObjectURL(downloadUrl.value)
  downloadUrl.value = ''
}

// 自動多次錄影，依設定次數與秒數重複錄影
async function autoRecord() {
  allBlobs.value = []
  for (let i = 0; i < recordTimes.value; i++) {
    startRecording()
    await wait(intervalSec.value * 1000)
    await stopRecording()
  }
}

// 下載所有影片
function downloadAll() {
  if (allBlobs.value.length === 0) return
  allBlobs.value.forEach((item, idx) => {
    const url = URL.createObjectURL(item.blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `record_${idx + 1}.${item.format}`
    a.click()
    URL.revokeObjectURL(url)
  })
}

// 通用等待函式
function wait(ms) {
  return new Promise(res => setTimeout(res, ms))
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

      <!-- 影片格式選擇 -->
      <el-select v-model="selectedFormat" placeholder="下載格式">
        <el-option label="WebM" value="webm" />
        <el-option label="MP4" value="mp4" />
      </el-select>

      <!-- 錄影與下載按鈕 -->
      <div class="btn-group">
        <el-button type="primary" @click="isRecording ? stopRecording() : startRecording()">
          {{ isRecording ? '停止錄影' : '開始錄影' }}
        </el-button>
        <el-button type="success" :disabled="!downloadUrl" @click="downloadVideo">
          下載影片
        </el-button>
      </div>

      <!-- 多次錄影設定與下載全部 -->
      <div class="multi-group">
        <el-input-number v-model="recordTimes" :min="1" label="錄影次數" />
        <el-input-number v-model="intervalSec" :min="1" label="每段秒數" />
        <el-button type="warning" @click="autoRecord">多次錄影</el-button>
        <el-button type="success" :disabled="allBlobs.length === 0" @click="downloadAll">下載所有影片</el-button>
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

.multi-group {
  margin-top: 20px;
  display: flex;
  gap: 10px;
  align-items: center;
}
</style>
