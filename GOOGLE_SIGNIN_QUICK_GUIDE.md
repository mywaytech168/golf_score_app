# ⚡ Google Sign-In Error 10 修复 - 快速指南

## 您的 SHA-1 (已确认)

复制此值:
```
05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
```

**注**: 这是您的生产/发布签名 SHA-1

---

## 2 步快速修复

### 第 1 步: 打开 Google Cloud Console

1. 访问: https://console.cloud.google.com
2. 确认右上角选择了您的项目
3. 左边菜单 → **APIs & Services** → **Credentials**

### 第 2 步: 添加 SHA-1 到 Google Cloud

1. 找到您的 Android Client ID
   - 应该显示: `446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9`

2. 点击它 (蓝色链接)

3. 点击编辑 (铅笔图标)

4. 向下滚动找 **SHA-1 certificates** 部分

5. 点击 **ADD FINGERPRINT**

6. 粘贴:
   ```
   05:CE:8D:27:F9:6B:44:6D:56:02:9F:9B:2B:DE:D0:77:BA:98:A5:26
   ```

7. 点击 **UPDATE** 保存

---

## 第 3 步: 等待 + 测试 (5-10 分钟)

等待 5-10 分钟让 Google 更新。

然后在手机上:
1. 关闭应用
2. 清除应用数据: Settings → Apps → Golf Score App → Storage → Clear Data  
3. 重新打开应用
4. 点击 **"使用 Google 登入"**
5. 应该看到 Google 登入对话框

---

## 完成 ✅

一旦 Google Sign-In 对话框出现，Error 10 就解决了!

**预计耗时**: 15 分钟
