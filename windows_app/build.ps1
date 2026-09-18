#Requires -Version 5.1
<#
  编译 Windows 客户端：自包含 + 单文件，这样同学电脑不用先装 .NET 运行时也能直接跑。

  用法（在 windows_app 目录下，或者项目根目录都行，脚本自己会 cd 过去）：
      powershell -ExecutionPolicy Bypass -File windows_app\build.ps1

  需要电脑上先装好 .NET 8 SDK（跑 dotnet --version 应该显示 8.x）。
  编译产物在：windows_app\bin\Release\net8.0-windows\win-x64\publish\CanvasDashboardWin.exe
#>

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "== 还原 + 编译 + 发布（Release / win-x64 / 自包含 / 单文件）==" -ForegroundColor Cyan

dotnet publish CanvasDashboard.csproj `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 编译失败，看上面的报错信息。" -ForegroundColor Red
    exit $LASTEXITCODE
}

$publishDir = Join-Path $PSScriptRoot "bin\Release\net8.0-windows\win-x64\publish"
$exePath = Join-Path $publishDir "CanvasDashboardWin.exe"

if (Test-Path $exePath) {
    Write-Host "✅ 编译完成：$exePath" -ForegroundColor Green
} else {
    Write-Host "⚠️ 没找到预期的 exe，检查一下上面 dotnet publish 的输出目录是不是有变化。" -ForegroundColor Yellow
}
