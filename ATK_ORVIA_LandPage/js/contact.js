/*
 * ORVIA 官網「聯絡我們」表單處理
 * ─────────────────────────────────────────────────────────────
 * 監聽 #contact-form，前端驗證後 POST 到後端 /api/contact。
 * 設計：全檔 no-op-safe — 表單不存在 / 欄位缺漏皆安靜略過，不在 console 噴錯。
 * GA：送出成功時若 window.gtag 存在，記 contact_submit{source:'web'}（比照 analytics.js 安全呼叫）。
 */
(function () {
  'use strict';

  var ENDPOINT = 'https://orvia.api.atk.tw/api/contact';

  // ── Cloudflare Turnstile 人機驗證 ───────────────────────────────
  // 填入 Cloudflare 後台的 Site Key 即啟用；留空字串 = 停用（表單照常運作）。
  var TURNSTILE_SITE_KEY = '0x4AAAAAADlA9V83Slp06dNr';
  var turnstileWidgetId = null;

  function turnstileLang() {
    var l = window.CONTACT_LANG;
    return l === 'en' ? 'en' : (l === 'cn' ? 'zh-CN' : 'zh-TW');
  }

  // 渲染 widget（turnstile api.js 載入完成 + DOM 就緒後才有效，兩條路徑都會呼叫）
  function renderTurnstile() {
    if (!TURNSTILE_SITE_KEY) return;
    if (turnstileWidgetId !== null) return;            // 已渲染
    if (!window.turnstile) return;                     // api.js 尚未載入
    var container = document.getElementById('cf-turnstile-widget');
    var field = document.getElementById('cf-turnstile-field');
    if (!container) return;
    try {
      turnstileWidgetId = window.turnstile.render(container, {
        sitekey: TURNSTILE_SITE_KEY,
        theme: 'dark',
        language: turnstileLang()
      });
      if (field) field.style.display = '';
    } catch (e) { /* 渲染失敗時不阻斷表單；後端在 SecretKey 已設時仍會擋 */ }
  }
  // api.js 以 ?onload=onTurnstileReady 載入後回呼此函式
  window.onTurnstileReady = renderTurnstile;

  function ready(fn) {
    if (document.readyState !== 'loading') { fn(); }
    else { document.addEventListener('DOMContentLoaded', fn); }
  }

  ready(function () {
    var form = document.getElementById('contact-form');
    if (!form) return; // 非聯絡頁，安靜略過

    renderTurnstile(); // api.js 若已先載入，這裡補渲染

    var statusEl = document.getElementById('cf-status');
    var submitBtn = form.querySelector('[type="submit"]');

    function resetTurnstile() {
      if (TURNSTILE_SITE_KEY && window.turnstile && turnstileWidgetId !== null) {
        try { window.turnstile.reset(turnstileWidgetId); } catch (e) { /* ignore */ }
      }
    }

    // 失敗收尾：解鎖按鈕 + 重置驗證（token 單次有效，重試需新 token）+ 顯示錯誤
    function fail(text) {
      setBusy(false);
      resetTurnstile();
      setStatus(text, false);
    }

    function val(id) {
      var el = document.getElementById(id);
      return el ? (el.value || '').trim() : '';
    }

    // 從頁面 I18N 取目前語言的狀態文案，取不到則用內建退回值
    function msg(key, fallback) {
      try {
        var dict = (window.CONTACT_I18N && window.CONTACT_LANG && window.CONTACT_I18N[window.CONTACT_LANG]) || null;
        if (dict && dict[key] !== undefined) return dict[key];
      } catch (e) { /* ignore */ }
      return fallback;
    }

    function setStatus(text, ok) {
      if (!statusEl) return;
      statusEl.textContent = text || '';
      statusEl.style.color = ok ? '#34d399' : '#f87171'; // 成功綠 / 失敗紅
    }

    function setBusy(busy) {
      if (!submitBtn) return;
      submitBtn.disabled = !!busy;
      submitBtn.style.opacity = busy ? '0.6' : '';
      submitBtn.style.cursor = busy ? 'not-allowed' : '';
    }

    function isValidEmail(s) {
      // 基本格式驗證，足夠擋掉明顯錯誤
      return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
    }

    function trackSubmit() {
      try {
        if (typeof window.gtag === 'function') {
          window.gtag('event', 'contact_submit', { source: 'web' });
        }
      } catch (e) { /* 永不影響頁面 */ }
    }

    form.addEventListener('submit', function (e) {
      e.preventDefault();
      if (submitBtn && submitBtn.disabled) return; // 防連點重送

      var name = val('cf-name');
      var email = val('cf-email');
      var subject = val('cf-subject');
      var message = val('cf-message');

      // 前端驗證
      if (!isValidEmail(email)) {
        setStatus(msg('cf.errEmail', '請輸入有效的 Email 地址。'), false);
        return;
      }
      if (!message) {
        setStatus(msg('cf.errMessage', '請填寫訊息內容。'), false);
        return;
      }

      // 人機驗證：啟用時必須先取得 token
      var captchaToken = '';
      if (TURNSTILE_SITE_KEY) {
        try {
          if (window.turnstile && turnstileWidgetId !== null) {
            captchaToken = window.turnstile.getResponse(turnstileWidgetId) || '';
          }
        } catch (e) { captchaToken = ''; }
        if (!captchaToken) {
          setStatus(msg('cf.errCaptcha', '請先完成人機驗證。'), false);
          return;
        }
      }

      setBusy(true);
      setStatus(msg('cf.sending', '傳送中…'), true);

      var payload = {
        name: name,
        email: email,
        subject: subject,
        message: message,
        source: 'web',
        turnstile: captchaToken
      };

      fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      }).then(function (res) {
        if (res.status === 429) {
          fail(msg('cf.errRate', '請求過於頻繁，請稍後再試。'));
          return;
        }
        if (!res.ok) {
          fail(msg('cf.errFail', '送出失敗，請稍後再試或直接來信 support@atk.tw。'));
          return;
        }
        // 嘗試解析 JSON；若非 JSON 也視同失敗處理
        res.json().then(function (data) {
          if (data && data.success === true) {
            resetTurnstile();
            setStatus(msg('cf.ok', '訊息已送出，我們會盡快回覆，謝謝！'), true);
            form.reset();
            setBusy(true); // 送出成功後保持 disable，避免重送
            trackSubmit();
          } else {
            fail(msg('cf.errFail', '送出失敗，請稍後再試或直接來信 support@atk.tw。'));
          }
        }).catch(function () {
          fail(msg('cf.errFail', '送出失敗，請稍後再試或直接來信 support@atk.tw。'));
        });
      }).catch(function () {
        // 網路錯誤
        fail(msg('cf.errNetwork', '網路連線發生問題，請檢查連線後再試。'));
      });
    });
  });
})();
