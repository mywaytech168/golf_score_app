using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

namespace UploadServer.Services
{
    public interface IEmailService
    {
        /// <summary>寄送密碼重設驗證碼信件</summary>
        Task SendPasswordResetCodeAsync(string toEmail, string toDisplayName, string code);

        /// <summary>
        /// 將「聯絡我們 / 意見回饋」轉寄到客服信箱（Smtp:SupportInbox，預設 support@atk.tw）。
        /// replyTo 設為使用者信箱，方便客服直接回覆。
        /// </summary>
        Task SendContactNotificationAsync(
            string source, string? name, string? replyToEmail, string? subject, string message);
    }

    public class SmtpEmailService : IEmailService
    {
        private readonly IConfiguration _config;
        private readonly ILogger<SmtpEmailService> _logger;

        public SmtpEmailService(IConfiguration config, ILogger<SmtpEmailService> logger)
        {
            _config = config;
            _logger = logger;
        }

        public async Task SendPasswordResetCodeAsync(
            string toEmail, string toDisplayName, string code)
        {
            var smtp    = _config.GetSection("Smtp");
            var host    = smtp["Host"]     ?? throw new InvalidOperationException("Smtp:Host 未設定");
            var port    = int.Parse(smtp["Port"] ?? "587");
            var user    = smtp["Username"] ?? throw new InvalidOperationException("Smtp:Username 未設定");
            var pass    = smtp["Password"] ?? throw new InvalidOperationException("Smtp:Password 未設定");
            var from    = smtp["From"]     ?? user;
            var fromName= smtp["FromName"] ?? "ORVIA";

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(fromName, from));
            message.To.Add(new MailboxAddress(toDisplayName, toEmail));
            message.Subject = "【ORVIA】密碼重設驗證碼";

            message.Body = new TextPart("html")
            {
                Text = $@"<!DOCTYPE html>
<html>
<head><meta charset='utf-8'></head>
<body style='font-family: Arial, sans-serif; background:#f4f6f9; padding:24px;'>
  <div style='max-width:480px; margin:0 auto; background:#fff; border-radius:16px;
              padding:32px; box-shadow:0 2px 8px rgba(0,0,0,0.08);'>
    <div style='text-align:center; margin-bottom:24px;'>
      <span style='font-size:32px;'>⛳</span>
      <h2 style='margin:8px 0 0; color:#1E8E5A; font-size:22px;'>ORVIA</h2>
    </div>
    <h3 style='color:#123B70; margin-bottom:8px;'>密碼重設</h3>
    <p style='color:#4A5568; margin-bottom:20px;'>您好 <strong>{toDisplayName}</strong>，<br>
    我們收到您的密碼重設申請，請在 App 中輸入以下 6 位驗證碼：</p>
    <div style='background:#f0faf4; border:2px solid #1E8E5A; border-radius:12px;
                padding:20px; text-align:center; margin:0 0 24px;'>
      <span style='font-size:40px; font-weight:900; letter-spacing:12px;
                   color:#123B70; font-family:monospace;'>{code}</span>
    </div>
    <p style='color:#6F7B86; font-size:14px; margin-bottom:4px;'>
      ⏰ 此驗證碼 <strong>15 分鐘</strong>內有效</p>
    <p style='color:#6F7B86; font-size:14px; margin-bottom:24px;'>
      🔒 請勿將此碼分享給任何人</p>
    <hr style='border:none; border-top:1px solid #E2E8F0; margin:0 0 16px;'>
    <p style='color:#9AA6B2; font-size:12px; text-align:center; margin:0;'>
      如果您沒有申請密碼重設，請忽略此信。<br>此信由系統自動發送，請勿回覆。</p>
  </div>
</body>
</html>"
            };

            using var client = new SmtpClient();
            await client.ConnectAsync(host, port, SecureSocketOptions.StartTls);
            await client.AuthenticateAsync(user, pass);
            await client.SendAsync(message);
            await client.DisconnectAsync(true);

            _logger.LogInformation("密碼重設驗證碼已寄至: {Email}", toEmail);
        }

        public async Task SendContactNotificationAsync(
            string source, string? name, string? replyToEmail, string? subject, string message)
        {
            var smtp     = _config.GetSection("Smtp");
            var host     = smtp["Host"]     ?? throw new InvalidOperationException("Smtp:Host 未設定");
            var port     = int.Parse(smtp["Port"] ?? "587");
            var user     = smtp["Username"] ?? throw new InvalidOperationException("Smtp:Username 未設定");
            var pass     = smtp["Password"] ?? throw new InvalidOperationException("Smtp:Password 未設定");
            var from     = smtp["From"]     ?? user;
            var fromName = smtp["FromName"] ?? "ORVIA";
            var inbox    = smtp["SupportInbox"] ?? "support@atk.tw";

            var safeName    = string.IsNullOrWhiteSpace(name) ? "（未填）" : name.Trim();
            var safeSubject = string.IsNullOrWhiteSpace(subject) ? "（無主旨）" : subject.Trim();
            var safeEmail   = string.IsNullOrWhiteSpace(replyToEmail) ? "（未填）" : replyToEmail.Trim();
            var sourceLabel = source == "app" ? "App" : "官網";

            var mail = new MimeMessage();
            mail.From.Add(new MailboxAddress(fromName, from));
            mail.To.Add(new MailboxAddress("ORVIA Support", inbox));
            // 客服按「回覆」直接回到使用者信箱
            if (!string.IsNullOrWhiteSpace(replyToEmail))
                mail.ReplyTo.Add(new MailboxAddress(safeName, replyToEmail.Trim()));
            mail.Subject = $"【ORVIA 聯絡表單 · {sourceLabel}】{safeSubject}";

            var bodyBuilder = new BodyBuilder
            {
                HtmlBody = $@"<!DOCTYPE html>
<html><head><meta charset='utf-8'></head>
<body style='font-family: Arial, sans-serif; background:#f4f6f9; padding:24px;'>
  <div style='max-width:560px; margin:0 auto; background:#fff; border-radius:16px;
              padding:28px; box-shadow:0 2px 8px rgba(0,0,0,0.08);'>
    <h3 style='color:#4A7FFF; margin:0 0 16px;'>新的聯絡表單訊息（{sourceLabel}）</h3>
    <table style='width:100%; border-collapse:collapse; font-size:14px; color:#333;'>
      <tr><td style='padding:6px 8px; color:#888; width:80px;'>姓名</td><td style='padding:6px 8px;'>{System.Net.WebUtility.HtmlEncode(safeName)}</td></tr>
      <tr><td style='padding:6px 8px; color:#888;'>Email</td><td style='padding:6px 8px;'>{System.Net.WebUtility.HtmlEncode(safeEmail)}</td></tr>
      <tr><td style='padding:6px 8px; color:#888;'>主旨</td><td style='padding:6px 8px;'>{System.Net.WebUtility.HtmlEncode(safeSubject)}</td></tr>
    </table>
    <hr style='border:none; border-top:1px solid #E2E8F0; margin:16px 0;'>
    <div style='font-size:15px; color:#1a1a1a; white-space:pre-wrap; line-height:1.6;'>{System.Net.WebUtility.HtmlEncode(message.Trim())}</div>
    <hr style='border:none; border-top:1px solid #E2E8F0; margin:16px 0;'>
    <p style='color:#9AA6B2; font-size:12px; margin:0;'>此信由 ORVIA 聯絡表單自動轉寄，直接「回覆」即可回信給使用者。</p>
  </div>
</body></html>"
            };
            mail.Body = bodyBuilder.ToMessageBody();

            using var client = new SmtpClient();
            await client.ConnectAsync(host, port, SecureSocketOptions.StartTls);
            await client.AuthenticateAsync(user, pass);
            await client.SendAsync(mail);
            await client.DisconnectAsync(true);

            _logger.LogInformation("聯絡表單訊息已轉寄客服信箱: {Inbox}（來源 {Source}）", inbox, source);
        }
    }
}
