<#
.SYNOPSIS
  assets/jmpsa_spots.json を最新化する更新ジョブ。

.DESCRIPTION
  以下を順に実行して同梱データを作り直す:
    1. dart run tool/harvest_jmpsa.dart        … 全47都道府県の一覧を取得
    2. dart run tool/enrich_displacement.dart  … 絞り込み用の排気量範囲を付与
  -WithDetails を付けると、さらに enrich_details.dart で全項目をオフライン用に焼き込む。

  更新前に既存JSONをバックアップし、生成物が不正(件数不足/壊れたJSON)の場合は
  バックアップへ自動復元する。半年に1回 Task Scheduler から起動される想定
  (register_jmpsa_update_task.ps1 で登録)。手動実行も可。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tool\update_jmpsa_spots.ps1

.NOTES
  dart は 1) -DartExe 指定 2) PATH 上の dart 3) $env:FLUTTER_ROOT\bin\dart.bat
  4) D:\flutter\bin\dart.bat の順で解決する。
#>
[CmdletBinding()]
param(
  # dart 実行ファイルを明示指定したい場合。
  [string]$DartExe,
  # これ未満の件数ならハーベスト失敗とみなしてバックアップへ復元する。
  [int]$MinSpotCount = 20000,
  # 詳細項目(TEL/料金/備考など)をオフライン用に焼き込む(時間がかかる)。
  [switch]$WithDetails,
  # dart pub get を省略する(依存解決済みで高速に回したいとき)。
  [switch]$SkipPubGet
)

# native(dart)の stderr で停止しないよう Stop にはしない。要所で $LASTEXITCODE を見る。
$ErrorActionPreference = 'Continue'

# --- プロジェクトルート(このスクリプトの1つ上)へ移動 ---
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

# --- ログ準備 ---
$logDir = Join-Path $projectRoot 'tool\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile = Join-Path $logDir "update-$stamp.log"

# 進捗はホスト(コンソール/標準出力)へ出す。Write-Output だと関数の戻り値ストリームを
# 汚し、Invoke-Step の戻り値が配列化して終了コード判定を誤るため使わない。
function Log([string]$msg) {
  $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
  Write-Host $line
  Add-Content -LiteralPath $logFile -Value $line -Encoding utf8
}

# dart の出力をログへ追記して終了コードを返す(全ストリームをファイルへ。stderr でも停止しない)。
# ※ 成功ストリームへ余計な値を出さないこと(戻り値が配列化し判定を誤るため)。
function Invoke-Step([string]$exe, [string[]]$dartArgs) {
  Log ("RUN: {0} {1}" -f $exe, ($dartArgs -join ' '))
  & $exe @dartArgs *>> $logFile
  return $LASTEXITCODE
}

# --- dart の解決 ---
function Resolve-Dart {
  if ($DartExe) { return $DartExe }
  $cmd = Get-Command dart -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  if ($env:FLUTTER_ROOT -and (Test-Path "$env:FLUTTER_ROOT\bin\dart.bat")) {
    return "$env:FLUTTER_ROOT\bin\dart.bat"
  }
  foreach ($p in @('D:\flutter\bin\dart.bat', 'C:\flutter\bin\dart.bat')) {
    if (Test-Path $p) { return $p }
  }
  throw 'dart が見つかりません。-DartExe で実行パスを指定してください。'
}

$target = Join-Path $projectRoot 'assets\jmpsa_spots.json'
$backup = $null

# 失敗時: バックアップへ復元してから異常終了する。
function Fail([string]$why) {
  Log "FAILED: $why"
  if ($backup -and (Test-Path $backup)) {
    Copy-Item -LiteralPath $backup -Destination $target -Force
    Log "restored backup -> $target"
  }
  exit 1
}

$dart = Resolve-Dart
Log "START update  project=$projectRoot  dart=$dart  withDetails=$WithDetails"

# --- 既存JSONをバックアップ(直近5世代だけ保持) ---
if (Test-Path $target) {
  $backupDir = Join-Path $projectRoot 'tool\backup'
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  $backup = Join-Path $backupDir "jmpsa_spots-$stamp.json"
  Copy-Item -LiteralPath $target -Destination $backup -Force
  Log ("backup -> {0} ({1:N0} bytes)" -f $backup, (Get-Item $backup).Length)
  Get-ChildItem -LiteralPath $backupDir -Filter 'jmpsa_spots-*.json' |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 5 |
    Remove-Item -Force -ErrorAction SilentlyContinue
}

# --- 依存解決 ---
if (-not $SkipPubGet) {
  if ((Invoke-Step $dart @('pub', 'get')) -ne 0) { Fail "dart pub get failed (exit $LASTEXITCODE)" }
}

# --- STEP 1: 一覧ハーベスト(約20分) ---
Log 'STEP 1: harvest_jmpsa.dart (全47都道府県の一覧取得, 約20〜40分) ...'
if ((Invoke-Step $dart @('run', 'tool/harvest_jmpsa.dart')) -ne 0) {
  Fail "harvest_jmpsa.dart failed (exit $LASTEXITCODE)"
}

# --- STEP 2: 排気量範囲の付与 ---
Log 'STEP 2: enrich_displacement.dart (絞り込み用の排気量範囲を付与) ...'
if ((Invoke-Step $dart @('run', 'tool/enrich_displacement.dart')) -ne 0) {
  Fail "enrich_displacement.dart failed (exit $LASTEXITCODE)"
}

# --- STEP 3(任意): 詳細項目の焼き込み ---
if ($WithDetails) {
  Log 'STEP 3: enrich_details.dart (詳細項目をオフライン用に焼き込み, 長時間) ...'
  if ((Invoke-Step $dart @('run', 'tool/enrich_details.dart')) -ne 0) {
    Fail "enrich_details.dart failed (exit $LASTEXITCODE)"
  }
}

# --- 生成物の検証 ---
if (-not (Test-Path $target)) { Fail 'output file missing' }
$count = 0
try {
  $json = Get-Content -LiteralPath $target -Raw -Encoding utf8 | ConvertFrom-Json
  $count = @($json).Count
} catch {
  Fail "output is not valid JSON: $($_.Exception.Message)"
}
Log ("validated: spotCount={0}  size={1:N0} bytes" -f $count, (Get-Item $target).Length)
if ($count -lt $MinSpotCount) { Fail "spotCount $count < MinSpotCount $MinSpotCount" }

Log "DONE: assets/jmpsa_spots.json updated ($count spots). log=$logFile"
exit 0
