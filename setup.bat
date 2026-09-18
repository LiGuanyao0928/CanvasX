@echo off
REM 第一次拿到这个项目时在 Windows 上跑一次就行。做三件事：
REM 1. 建 Python 虚拟环境 + 装依赖
REM 2. 编译 Windows 原生客户端（WPF，自包含单文件）
REM 3. 打开客户端——第一次打开会自动出现设置向导，跟着填你自己的 Canvas 账号信息就行
REM
REM 需要电脑上已经有：.NET 8 SDK、Python 3（装的时候记得勾选 "Add python.exe to PATH"）
REM
REM 用法：双击这个文件，或者在命令提示符里跑 setup.bat
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo == 1/3 创建虚拟环境 + 安装依赖 ==
if not exist ".venv" (
    python -m venv .venv
    if errorlevel 1 (
        echo 创建虚拟环境失败，确认一下 Python 3 装好了、而且勾了 "Add python.exe to PATH"。
        exit /b 1
    )
)
.venv\Scripts\python.exe -m pip install --upgrade pip --quiet
.venv\Scripts\python.exe -m pip install -r requirements.txt --quiet
if errorlevel 1 (
    echo 安装 Python 依赖失败，看上面的报错信息。
    exit /b 1
)
echo Python 环境准备好了

echo == 2/3 编译 Windows 客户端 ==
powershell -ExecutionPolicy Bypass -File "windows_app\build.ps1"
if errorlevel 1 (
    echo 编译失败，需要先装好 .NET 8 SDK（跑 dotnet --version 检查）。看上面的报错信息。
    exit /b 1
)

set "EXE_PATH=windows_app\bin\Release\net8.0-windows\win-x64\publish\CanvasDashboardWin.exe"

echo == 3/3 打开客户端 ==
if exist "logs" (
    rem 已存在，跳过
) else (
    mkdir logs
)

if exist "%EXE_PATH%" (
    start "" "%EXE_PATH%"
    echo 完成！第一次打开会看到设置向导，跟着填你自己的 Canvas 网址/Token/要追踪的课程就行。
) else (
    echo 没找到编译好的 exe（%EXE_PATH%），去 windows_app\README.md 看看构建说明，自己手动排查一下。
    exit /b 1
)

endlocal
