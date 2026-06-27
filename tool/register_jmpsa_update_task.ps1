<#
.SYNOPSIS
  assets/jmpsa_spots.json を半年に1回更新する Windows タスクを登録する。

.DESCRIPTION
  毎年 1月1日 と 7月1日(=半年ごと)の指定時刻に update_jmpsa_spots.ps1 を実行する
  スケジュールタスクを作成する。管理者権限の PowerShell で実行すること。

.EXAMPLE
  # 既定(1月1日・7月1日 03:00 に実行)で登録
  powershell -NoProfile -ExecutionPolicy Bypass -File tool\register_jmpsa_update_task.ps1

.EXAMPLE
  # 実行時刻を変える / 詳細項目も焼き込む
  ... register_jmpsa_update_task.ps1 -Time 04:30 -WithDetails

.NOTES
  - 既定では「ログオン中のユーザー」で実行される。ログオフ中でも動かしたい場合は
    -RunAsUser / -Password を指定する(資格情報を保存して実行)。
  - 登録解除: schtasks /Delete /TN "MotoPark\UpdateJmpsaSpots" /F
  - 手動テスト: schtasks /Run /TN "MotoPark\UpdateJmpsaSpots"
#>
[CmdletBinding()]
param(
  [string]$TaskName = 'MotoPark\UpdateJmpsaSpots',
  # 実行時刻 (HH:mm)
  [string]$Time = '03:00',
  # 詳細項目もオフライン用に焼き込む(更新ジョブに -WithDetails を渡す)。
  [switch]$WithDetails,
  # ログオフ中も実行したい場合に使う実行ユーザーとパスワード。
  [string]$RunAsUser,
  [string]$Password
)

$ErrorActionPreference = 'Stop'

$worker = Join-Path $PSScriptRoot 'update_jmpsa_spots.ps1'
if (-not (Test-Path $worker)) { throw "更新ジョブが見つかりません: $worker" }

# 実行コマンド(タスクが起動する中身)。
$inner = "-NoProfile -ExecutionPolicy Bypass -File `"$worker`""
if ($WithDetails) { $inner += ' -WithDetails' }
$tr = "powershell.exe $inner"

# schtasks 引数を組み立てる。
#   /SC MONTHLY /M JAN,JUL /D 1  → 1月と7月の1日(=半年ごと)に実行。
$argList = @(
  '/Create',
  '/TN', $TaskName,
  '/TR', $tr,
  '/SC', 'MONTHLY',
  '/M', 'JAN,JUL',
  '/D', '1',
  '/ST', $Time,
  '/RL', 'HIGHEST',
  '/F'
)
if ($RunAsUser) {
  $argList += @('/RU', $RunAsUser)
  if ($Password) { $argList += @('/RP', $Password) }
}

Write-Output "登録コマンド: schtasks $($argList -join ' ')"
& schtasks.exe @argList
if ($LASTEXITCODE -ne 0) { throw "schtasks の登録に失敗しました (exit $LASTEXITCODE)" }

Write-Output ''
Write-Output "登録しました: $TaskName  (毎年 1月1日 と 7月1日 $Time に実行)"
Write-Output "手動テスト  : schtasks /Run /TN `"$TaskName`""
Write-Output "状態確認    : schtasks /Query /TN `"$TaskName`" /V /FO LIST"
Write-Output "登録解除    : schtasks /Delete /TN `"$TaskName`" /F"
