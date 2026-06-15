/*
 * ORVIA 官網 Google Analytics 4 (GA4)
 * ─────────────────────────────────────────────────────────────
 * 設定步驟（需你的 Google 帳號）：
 *   1. 進 GA4 後台（建議與 App 同一個 property：Firebase golf-score-app-485702 連結的那個）
 *      Admin → 資料串流 (Data Streams) → 新增串流 → 「網站 Web」
 *      網站網址填 https://orvia.atk.tw ，取得「評估 ID / Measurement ID」格式為 G-XXXXXXXXXX
 *   2. 把下面的 GA_MEASUREMENT_ID 換成你的 G-ID（或告訴我，我幫你填）
 *
 * 設計：未填 ID 時自動停用（不載入、不報錯），與 App 端 AnalyticsService「未設定即 no-op」一致。
 * 自動追蹤：每頁載入的 page_view（GA4 內建，知道使用者在哪一頁）。
 * 自訂事件：download_click{store}、language_switch{lang}。
 */
(function () {
  'use strict';

  var GA_MEASUREMENT_ID = 'G-XXXXXXXXXX'; // ← 替換成你的 GA4 Web 評估 ID

  // 尚未設定 ID：停用，避免噪音
  if (!GA_MEASUREMENT_ID || GA_MEASUREMENT_ID.indexOf('G-') !== 0 || GA_MEASUREMENT_ID === 'G-XXXXXXXXXX') {
    if (window.console) console.warn('[Analytics] GA_MEASUREMENT_ID 尚未設定，網站分析停用');
    return;
  }

  // 載入 gtag.js
  var tag = document.createElement('script');
  tag.async = true;
  tag.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(GA_MEASUREMENT_ID);
  document.head.appendChild(tag);

  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag('js', new Date());
  gtag('config', GA_MEASUREMENT_ID); // 自動送出本頁 page_view

  function track(name, params) {
    try { gtag('event', name, params || {}); } catch (e) { /* 永不影響頁面 */ }
  }

  // 判斷一個連結是不是「下載 / 商店」動作，回傳 store 名稱或 null
  function storeOf(el) {
    var a = el.closest ? el.closest('a') : null;
    if (!a) return null;
    if (a.hasAttribute('data-store')) return a.getAttribute('data-store');
    var href = (a.getAttribute('href') || '').toLowerCase();
    var text = (a.textContent || '').toLowerCase();
    if (href.indexOf('play.google.com') > -1 || text.indexOf('google play') > -1) return 'google_play';
    if (href.indexOf('apps.apple.com') > -1 || text.indexOf('app store') > -1) return 'app_store';
    // 子頁的「下載 ORVIA App」CTA、或指向下載區/ app.html 的按鈕
    if (href.indexOf('#download') > -1 || href.indexOf('app.html') > -1 || text.indexOf('下載') > -1) return 'generic';
    return null;
  }

  document.addEventListener('DOMContentLoaded', function () {
    // 用事件委派：涵蓋所有頁面的下載/商店按鈕，無需逐一加屬性
    document.addEventListener('click', function (e) {
      var store = storeOf(e.target);
      if (store) track('download_click', { store: store });

      var langBtn = e.target.closest ? e.target.closest('.lang-switch button[data-lang]') : null;
      if (langBtn) track('language_switch', { lang: langBtn.getAttribute('data-lang') });
    }, true);
  });
})();
