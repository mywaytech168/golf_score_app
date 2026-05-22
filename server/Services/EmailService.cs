using MailKit.Net.Smtp;
using MailKit.Security;
using MimeKit;

namespace UploadServer.Services
{
    public interface IEmailService
    {
        /// <summary>寄送密碼重設驗證碼信件</summary>
        Task SendPasswordResetCodeAsync(string toEmail, string toDisplayName, string code);
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
            var fromName= smtp["FromName"] ?? "TekSwing";

            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(fromName, from));
            message.To.Add(new MailboxAddress(toDisplayName, toEmail));
            message.Subject = "【TekSwing】密碼重設驗證碼";

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
      <h2 style='margin:8px 0 0; color:#1E8E5A; font-size:22px;'>TekSwing</h2>
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
    }
}
