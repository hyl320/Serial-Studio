<#
.SYNOPSIS
    Serial Studio 自动化环境自检与沙盒引导脚本 (Bootstrap Script)
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "   Serial Studio 自动化环境自检与沙盒引导 (Bootstrap)          " -ForegroundColor Cyan
Write-Host "==============================================================" -ForegroundColor Cyan

# 1. 查找 Visual Studio 2022
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = $null
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
}

if (-not $vsPath -or -not (Test-Path $vsPath)) {
    Write-Host "[X] 未检测到可用的 Visual Studio (MSVC x64) 安装！" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] 检测到 Visual Studio: $vsPath" -ForegroundColor Green

# 2. 查找 Qt 6.x (msvc2022_64)
$candidateQtPaths = @(
    "D:\qt5\6.8.0\msvc2022_64",
    "D:\qt5\6.11.2\msvc2022_64",
    "C:\Qt\6.8.0\msvc2022_64",
    "C:\Qt\6.11.2\msvc2022_64",
    "D:\Qt\6.8.0\msvc2022_64"
)

$qtPath = $null
if ($env:QTDIR -and (Test-Path "$env:QTDIR\bin\qmake.exe")) {
    $qtPath = $env:QTDIR
} else {
    foreach ($c in $candidateQtPaths) {
        if (Test-Path "$c\bin\qmake.exe") {
            $qtPath = $c
            break
        }
    }
}

if (-not $qtPath) {
    Write-Host "[X] 未能在常见目录自动发现 Qt 6 (msvc2022_64)！" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] 检测到 Qt 6 工具链: $qtPath" -ForegroundColor Green

# 3. 环境变量诊断
$polluted = $false
foreach ($entry in ($env:PATH -split ';')) {
    if ($entry -like "*msys64*" -or $entry -like "*mingw*") {
        $polluted = $true
        break
    }
}
if ($polluted) {
    Write-Host "[!] 检测到系统 PATH 中存在 MinGW / MSYS2 工具链路径" -ForegroundColor Yellow
    Write-Host "    -> 正在自动激活局部沙盒配置，在项目内优先置顶 MSVC 与 Qt 6..." -ForegroundColor Green
} else {
    Write-Host "[OK] 全局 PATH 环境干净" -ForegroundColor Green
}

# 4. 生成/刷新 CMakePresets.json
$projectDir = $PSScriptRoot
$qtForwardSlash = $qtPath.Replace('\', '/')

$presetsTemplate = @'
{
  "version": 3,
  "configurePresets": [
    {
      "name": "windows-base",
      "hidden": true,
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/out/build/${presetName}",
      "installDir": "${sourceDir}/out/install/${presetName}",
      "architecture": {
        "value": "x64",
        "strategy": "external"
      },
      "toolset": {
        "value": "host=x64",
        "strategy": "external"
      },
      "cacheVariables": {
        "CMAKE_PREFIX_PATH": "__QT_PATH__",
        "BUILD_GPL3": "ON",
        "WITH_WEBENGINE": "OFF"
      }
    },
    {
      "name": "x64-Release",
      "displayName": "x64 Release (RelWithDebInfo)",
      "description": "Visual Studio 2022 x64 RelWithDebInfo build",
      "inherits": "windows-base",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "RelWithDebInfo"
      }
    },
    {
      "name": "x64-Debug",
      "displayName": "x64 Debug",
      "description": "Visual Studio 2022 x64 Debug build",
      "inherits": "windows-base",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug"
      }
    }
  ],
  "buildPresets": [
    {
      "name": "x64-Release",
      "configurePreset": "x64-Release"
    },
    {
      "name": "x64-Debug",
      "configurePreset": "x64-Debug"
    }
  ]
}
'@

$presetsOutput = $presetsTemplate.Replace('__QT_PATH__', $qtForwardSlash)
[System.IO.File]::WriteAllText("$projectDir\CMakePresets.json", $presetsOutput, [System.Text.Encoding]::UTF8)
Write-Host "[OK] 已生成/刷新 CMakePresets.json" -ForegroundColor Green

# 5. 生成/刷新 CMakeSettings.json
$settingsTemplate = @'
{
  "configurations": [
    {
      "name": "x64-Release",
      "generator": "Ninja",
      "configurationType": "RelWithDebInfo",
      "inheritEnvironments": [ "msvc_x64_x64" ],
      "buildRoot": "${projectDir}\\out\\build\\${name}",
      "installRoot": "${projectDir}\\out\\install\\${name}",
      "variables": [
        {
          "name": "CMAKE_PREFIX_PATH",
          "value": "__QT_PATH__"
        },
        {
          "name": "BUILD_GPL3",
          "value": "ON",
          "type": "BOOL"
        },
        {
          "name": "WITH_WEBENGINE",
          "value": "OFF",
          "type": "BOOL"
        }
      ]
    },
    {
      "name": "x64-Debug",
      "generator": "Ninja",
      "configurationType": "Debug",
      "inheritEnvironments": [ "msvc_x64_x64" ],
      "buildRoot": "${projectDir}\\out\\build\\${name}",
      "installRoot": "${projectDir}\\out\\install\\${name}",
      "variables": [
        {
          "name": "CMAKE_PREFIX_PATH",
          "value": "__QT_PATH__"
        },
        {
          "name": "BUILD_GPL3",
          "value": "ON",
          "type": "BOOL"
        },
        {
          "name": "WITH_WEBENGINE",
          "value": "OFF",
          "type": "BOOL"
        }
      ]
    }
  ]
}
'@

$settingsOutput = $settingsTemplate.Replace('__QT_PATH__', $qtForwardSlash)
[System.IO.File]::WriteAllText("$projectDir\CMakeSettings.json", $settingsOutput, [System.Text.Encoding]::UTF8)
Write-Host "[OK] 已生成/刷新 CMakeSettings.json" -ForegroundColor Green

# 6. 生成/刷新 .vscode/settings.json
$vscodeDir = "$projectDir\.vscode"
if (-not (Test-Path $vscodeDir)) { New-Item -ItemType Directory -Path $vscodeDir | Out-Null }

$vscodeTemplate = @'
{
  "cmake.generator": "Ninja",
  "cmake.buildDirectory": "${workspaceFolder}/out/build/${buildType}",
  "cmake.installPrefix": "${workspaceFolder}/out/install/${buildType}",
  "cmake.configureSettings": {
    "CMAKE_PREFIX_PATH": "__QT_PATH__",
    "BUILD_GPL3": "ON"
  },
  "cmake.environment": {
    "PATH": "__QT_BIN__;${env:PATH}"
  },
  "cmake.configureEnvironment": {
    "PATH": "__QT_BIN__;${env:PATH}"
  }
}
'@

$qtBinEscaped = "$qtPath\bin".Replace('\', '\\')
$vscodeOutput = $vscodeTemplate.Replace('__QT_PATH__', $qtForwardSlash).Replace('__QT_BIN__', $qtBinEscaped)
[System.IO.File]::WriteAllText("$vscodeDir\settings.json", $vscodeOutput, [System.Text.Encoding]::UTF8)
Write-Host "[OK] 已生成/刷新 .vscode/settings.json (沙盒已激活)" -ForegroundColor Green

# 7. 重置崩溃守卫注册表
try {
    $crashRegPath = "HKCU:\Software\Alex Spataru\Serial-Studio\Crash"
    if (Test-Path $crashRegPath) {
        Set-ItemProperty -Path $crashRegPath -Name "ConsecutiveCount" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $crashRegPath -Name "Running" -Value $false -ErrorAction SilentlyContinue
        Write-Host "[OK] 已重置 Serial Studio 崩溃守卫计数为 0" -ForegroundColor Green
    }
} catch {}

Write-Host "==============================================================" -ForegroundColor Cyan
Write-Host "  环境配置与沙盒化全部就绪！你可以：" -ForegroundColor Cyan
Write-Host "  1. 打开 Visual Studio 2022 -> 选择 x64-Release -> 按 F5 调试运行"
Write-Host "  2. 打开 VS Code -> 按 F5 调试运行"
Write-Host "==============================================================" -ForegroundColor Cyan
