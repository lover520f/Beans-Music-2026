@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================
echo   Beans Music 服务器启动器
echo   首次运行会自动创建虚拟环境并安装依赖
echo   启动后请保持本窗口开启
echo   浏览器打开: http://127.0.0.1:8765
echo ============================================
echo.
if not exist ".venv\Scripts\python.exe" (
  echo [1/3] 创建 Python 虚拟环境...
  py -3.11 -m venv .venv
  if errorlevel 1 (
    echo 未找到 Python 3.11，尝试默认 python 命令...
    python -m venv .venv
  )
  echo [2/3] 安装依赖（约 2~5 分钟，请耐心等待）...
  ".venv\Scripts\python.exe" -m pip install --upgrade pip -q
  ".venv\Scripts\python.exe" -m pip install -r requirements.txt
)
echo [3/3] 启动服务器...
".venv\Scripts\python.exe" server.py
pause
