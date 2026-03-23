# ⚡ 快速行动清单 - 立即执行

## 🔴 当前阻挡

系统有 **Java 11**，但 Gradle 需要 **Java 17**。

**解决**: 已自动配置。现在需要 **重启终端**。

---

## 3 步立即修复

### 📍 步骤 1: 关闭所有窗口 (30秒)

- 关闭 VS Code: `Alt + F4`
- 关闭所有命令行窗口
- 等待 5 秒

### 📍 步骤 2: 打开新命令行 (1分钟)

```bash
# Windows: 按 Win 键 → 输入 cmd → 按 Enter
cmd

# 验证 Java（应该显示 11.0.12）
java -version

# 验证 JAVA_HOME（应该显示 C:\Program Files\Microsoft\jdk-11.0.12.7-hotspot）
echo %JAVA_HOME%
```

### 📍 步骤 3: 获取 SHA1 (2分钟)

```bash
cd d:\project\golf\golf-score_app_1\android
gradlew.bat signingReport
```

寻找输出中的这一行:
```
SHA1: AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD
```

**复制这个值** (带冒号)

---

## 4️⃣ 步骤 4: 添加到 Google Cloud (5分钟)

1. 打开: `https://console.cloud.google.com`

2. **APIs & Services** → **Credentials**

3. 找到 Android Client ID: 
   ```
   446697241300-vqnlo2l37q8i404n1pa8hg299 1c0ffe9
   ```

4. 点击它 → 编辑 (铅笔图标)

5. 找到 **SHA-1 certificates**

6. 点击 **ADD FINGERPRINT**

7. 粘贴您的 SHA1 值

8. **UPDATE** 保存

---

## ⏰ 步骤 5: 等待并测试 (10分钟)

等待 5-10 分钟让 Google 更新。

然后重新构建:

```bash
cd d:\project\golf\golf-score_app_1
flutter clean
flutter pub get
flutter run
```

点击 **Google 登入** → 应该工作! ✅

---

## ❌ 如果还是失败

检查清单:

- [ ] Java version 是 11 或以上?  
  ```bash
  java -version
  ```

- [ ] JAVA_HOME 设置正确?  
  ```bash
  echo %JAVA_HOME%
  ```

- [ ] SHA1 确实添加到 Google Cloud?

- [ ] 等待了 10+ 分钟?

- [ ] 清除了应用数据?  
  在手机上: Settings → Apps → Golf Score App → Storage → Clear Data

---

## 📝 当前配置状态

✅ **Android**: 客户端 ID 已配置  
⏳ **iOS**: 需要客户端 ID (暂时跳过)  
🚀 **后端**: OAuth 验证在进行中  

---

**总耗时**: ~20 分钟  
**难度**: ⭐ 简单  
**风险**: ✅ 无风险 (无代码修改)

开始了吗? 👉 去关闭 VS Code!
