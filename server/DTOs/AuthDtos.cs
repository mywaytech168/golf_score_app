using System;
using System.Collections.Generic;

namespace UploadServer.DTOs
{
    /// <summary>
    /// 身份驗證相關 DTOs
    /// </summary>

    // ============================================================
    // 註冊相關
    // ============================================================
    public class RegisterRequest
    {
        public string Username { get; set; }
        public string Email { get; set; }
        public string Password { get; set; }
        public string DisplayName { get; set; }
    }

    public class RegisterResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; }
        public UserDto User { get; set; }
    }

    // ============================================================
    // 登入相關（本地帳號）
    // ============================================================
    public class LoginRequest
    {
        public string Username { get; set; }
        public string Password { get; set; }
    }

    public class LoginResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; }
        public string Token { get; set; }
        public string RefreshToken { get; set; }
        public UserDto User { get; set; }
    }

    // ============================================================
    // Google OAuth 相關
    // ============================================================
    public class GoogleLoginRequest
    {
        /// <summary>
        /// Google ID Token (from google_sign_in package)
        /// </summary>
        public string IdToken { get; set; }

        /// <summary>
        /// Google Access Token (可選)
        /// </summary>
        public string? AccessToken { get; set; }

        /// <summary>
        /// User's email from Google
        /// </summary>
        public string? Email { get; set; }

        /// <summary>
        /// User's display name from Google
        /// </summary>
        public string? DisplayName { get; set; }

        /// <summary>
        /// User's avatar URL from Google
        /// </summary>
        public string? AvatarUrl { get; set; }
    }

    public class GoogleLoginResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; }
        public string Token { get; set; }
        public string RefreshToken { get; set; }
        public UserDto User { get; set; }
    }

    // ============================================================
    // Token 刷新
    // ============================================================
    public class RefreshTokenRequest
    {
        public string RefreshToken { get; set; }
    }

    public class RefreshTokenResponse
    {
        public bool Success { get; set; }
        public string Token { get; set; }
        public string RefreshToken { get; set; }
    }

    // ============================================================
    // 用戶資訊
    // ============================================================
    public class UserDto
    {
        public string Id { get; set; }
        public string Username { get; set; }
        public string Email { get; set; }
        public string DisplayName { get; set; }
        public string AvatarUrl { get; set; }
        /// <summary>已綁定的登入提供商清單，e.g. ["local"], ["google"], ["local","google"]</summary>
        public List<string> Providers { get; set; } = new();
        public string Status { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? LastLoginAt { get; set; }
    }

    // ============================================================
    // 登出
    // ============================================================
    public class LogoutRequest
    {
        public int UserId { get; set; }
        public string Token { get; set; }
    }

    public class LogoutResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; }
    }

    // ============================================================
    // 密碼變更
    // ============================================================
    public class ChangePasswordRequest
    {
        public string OldPassword { get; set; }
        public string NewPassword { get; set; }
    }

    public class ChangePasswordResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; }
    }

    // ============================================================
    // 忘記密碼 / 重設密碼
    // ============================================================

    public class ForgotPasswordRequest
    {
        /// <summary>使用者 Email</summary>
        public string Email { get; set; } = "";
    }

    public class ForgotPasswordResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; } = "";
    }

    public class ResetPasswordRequest
    {
        /// <summary>申請時的 Email</summary>
        public string Email { get; set; } = "";
        /// <summary>信件中的 6 位數驗證碼</summary>
        public string Code { get; set; } = "";
        /// <summary>新密碼（須符合強度規則）</summary>
        public string NewPassword { get; set; } = "";
    }

    public class ResetPasswordResponse
    {
        public bool Success { get; set; }
        public string Message { get; set; } = "";
    }
}
