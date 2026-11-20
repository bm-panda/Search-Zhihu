param($paramPath)

# 盒子把参数 JSON 的路径作为第一个位置参数传入
if (-not $paramPath -and $args.Count -gt 0) { $paramPath = $args[0] }

function Show-Bubble {
    param(
        [string]$ApiBase,
        [ValidateSet("success", "error", "info")][string]$Type,
        [string]$Message,
        [int]$Duration = 3000
    )
    if ([string]::IsNullOrWhiteSpace($ApiBase)) { return }
    try {
        $json = @{ notify_type = $Type; message = $Message; duration = $Duration } | ConvertTo-Json -Compress
        # PowerShell 5.1 用字符串作 Body 会按本地代码页发送，中文会乱码，这里显式转成 UTF-8 字节
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        Invoke-RestMethod -Method Post -Uri "$ApiBase/api/notify" -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 5 | Out-Null
    } catch { }
}

if (-not $paramPath) {
    Write-Output (@{ status = "error"; message = "缺少参数文件路径" } | ConvertTo-Json -Compress)
    exit 1
}

try {
    $payload = Get-Content -LiteralPath $paramPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Output (@{ status = "error"; message = "无法解析参数文件: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
    exit 1
}

$envInfo = $payload.environment
$data = $payload.data
$apiBase = if ($envInfo) { [string]$envInfo.api_base } else { "" }

# 超级复制带剪贴板文本，搜索触发带搜索框文本，两者都写进 data.target_text
$keyword = ""
if ($data -and $data.target_text) {
    $keyword = [string](@($data.target_text) | Select-Object -First 1)
}

# 搜索框里可以用「知乎 关键词」「zhihu: 关键词」显式指定本脚本，搜索前去掉这段前缀
$keyword = $keyword -replace '^\s*(知乎|zhihu)\s*[:：]?\s+', ''
# 复制来的多行文本压成一行，避免把换行带进 URL
$keyword = ($keyword -replace '\s+', ' ').Trim()

if ([string]::IsNullOrWhiteSpace($keyword)) {
    Show-Bubble -ApiBase $apiBase -Type "info" -Message "请先复制文本，或在盒子搜索框输入关键词后再运行"
    Write-Output (@{ status = "info"; message = "搜索关键词为空" } | ConvertTo-Json -Compress)
    exit 0
}

# 知乎站内搜索：type=content 搜「内容」（回答/文章），EscapeDataString 负责中文与特殊符号编码
$url = "https://www.zhihu.com/search?type=content&q=$([uri]::EscapeDataString($keyword))"

try {
    Start-Process -FilePath $url
} catch {
    try {
        [System.Diagnostics.Process]::Start($url) | Out-Null
    } catch {
        Show-Bubble -ApiBase $apiBase -Type "error" -Message "打开浏览器失败：$($_.Exception.Message)"
        Write-Output (@{ status = "error"; message = "打开浏览器失败: $($_.Exception.Message)" } | ConvertTo-Json -Compress)
        exit 1
    }
}

Write-Output (@{ status = "ok"; keyword = $keyword; url = $url } | ConvertTo-Json -Compress)
