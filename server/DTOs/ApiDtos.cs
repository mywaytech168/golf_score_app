using System;
using System.Collections.Generic;

namespace UploadServer.DTOs
{
    /// <summary>
    /// 上傳切片請求 DTO
    /// </summary>
    public class UploadSliceRequest
    {
        public int VideoId { get; set; }
        public int SliceIndex { get; set; }
        public IFormFile VideoFile { get; set; }
        public IFormFile TrajectoryCSV { get; set; }
    }
    
    /// <summary>
    /// 上傳切片響應 DTO
    /// </summary>
    public class UploadSliceResponse
    {
        public bool Success { get; set; }
        public int SliceId { get; set; }
        public int VideoId { get; set; }
        public string Status { get; set; }
        public string Message { get; set; }
    }
    
    /// <summary>
    /// 視頻狀態響應 DTO
    /// </summary>
    public class VideoStatusResponse
    {
        public int VideoId { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        public DateTime UploadTime { get; set; }
        public int TotalSlices { get; set; }
        public int CompletedSlices { get; set; }
        public int FailedSlices { get; set; }
        public int ProcessingSlices { get; set; }
        public List<SliceStatusDto> Slices { get; set; } = new List<SliceStatusDto>();
    }
    
    /// <summary>
    /// 切片狀態 DTO
    /// </summary>
    public class SliceStatusDto
    {
        public int Id { get; set; }
        public int Index { get; set; }
        public string Status { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ProcessedAt { get; set; }
        public List<string> OutputFiles { get; set; } = new List<string>();
    }
    
    /// <summary>
    /// 視頻列表項目 DTO
    /// </summary>
    public class VideoListItemDto
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Status { get; set; }
        public DateTime UploadTime { get; set; }
        public int TotalSlices { get; set; }
        public int CompletedSlices { get; set; }
        public int FailedSlices { get; set; }
        public int ProcessingSlices { get; set; }
    }
    
    /// <summary>
    /// 獲取視頻列表響應 DTO
    /// </summary>
    public class GetVideosResponse
    {
        public bool Success { get; set; }
        public List<VideoListItemDto> Data { get; set; } = new List<VideoListItemDto>();
        public PaginationInfo Pagination { get; set; }
    }
    
    /// <summary>
    /// 分頁信息 DTO
    /// </summary>
    public class PaginationInfo
    {
        public int Page { get; set; }
        public int Limit { get; set; }
        public int Total { get; set; }
        public int Pages { get; set; }
    }
}
