using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

// 允許所有來源，以方便本地開發測試
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

var app = builder.Build();

app.UseCors();

// 上傳目錄
var uploadDir = Path.Combine(app.Environment.ContentRootPath, "Uploads");
Directory.CreateDirectory(uploadDir);

// 提供靜態檔案服務，影片可直接由 /videos/{檔名} 取得
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(uploadDir),
    RequestPath = "/videos"
});

// 取得影片檔案清單
app.MapGet("/videos", () =>
{
    var files = Directory.GetFiles(uploadDir)
        .Select(Path.GetFileName)
        .Where(name => name != null)
        .ToArray();
    return Results.Json(files);
});

// 上傳影片檔案
app.MapPost("/upload", async (HttpRequest request) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest("缺少表單資料");
    }

    var form = await request.ReadFormAsync();
    var file = form.Files.FirstOrDefault();
    if (file == null)
    {
        return Results.BadRequest("找不到檔案");
    }

    var filePath = Path.Combine(uploadDir, file.FileName);
    using var stream = File.Create(filePath);
    await file.CopyToAsync(stream);
    return Results.Ok(new { file.FileName });
});

app.Run();
