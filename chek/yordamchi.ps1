# ============================================================
#  OLIMP ZAGOTOVKA - MONOBLOK YORDAMCHISI
#  Bulutdan topshiriq so'rab turadi, bajaradi va natijasini qaytaradi.
#
#  2026-11-18, egasi so'rovi: "shu kompyuter bilan ishlashimiz uchun unga
#  qanday kira olasan, to'liq dostup bilan kirib o'zing tuzatishingni
#  hohlayman". Monoblokka TASHQARIDAN kirib bo'lmaydi: ikkala kompyuterda
#  ham administrator huquqi yo'q (WinRM/SSH shuni talab qiladi), monoblok
#  ichki tarmoqda, port ochilmagan. Shuning uchun chek agentidagi usul
#  takrorlanadi -- monoblok O'ZI bulutga murojaat qiladi. Hech kim bu
#  kompyuterga kirmaydi, u o'zi so'raydi.
#
#  XAVFSIZLIK:
#    - Kalit faylda YO'Q, buyruq satrida beriladi (ombor ochiq).
#    - Har bir topshiriq va natijasi `yordamchi_log.txt` ga yoziladi,
#      bulutdagi bazada ham saqlanadi -- keyin tekshirish mumkin.
#    - TO'XTATISH: shu papkada `yordamchi_STOP.txt` nomli fayl yaratilsa
#      hech qanday buyruq bajarilmaydi (dastur o'chmaydi, faqat rad etadi).
#      Butunlay o'chirish uchun Автозагрузка dagi faylni qayta nomlang.
#    - Bu foydalanuvchida admin huquqi yo'q, ya'ni Windows sozlamalarini
#      o'zgartirib bo'lmaydi.
#    - Har topshiriqqa vaqt chegarasi bor (sukut bo'yicha 5 daqiqa),
#      osilib qolgani majburan to'xtatiladi.
# ============================================================
param(
  [Parameter(Mandatory = $true)][string]$Key,
  [int]$VaqtChegarasiDaqiqa = 5
)

$ENDPOINT = "https://zagotovka-zayavka-send.olimpzagotovka.workers.dev/internal/yordamchi/soz"
$LOG      = Join-Path $PSScriptRoot "yordamchi_log.txt"
$HOLAT    = Join-Path $PSScriptRoot "yordamchi_holat.txt"
$STOP     = Join-Path $PSScriptRoot "yordamchi_STOP.txt"
$TIMEOUT  = 30          # bulut liniyani 12 soniya ushlaydi, zahira bilan
$INTERVAL = 0.3
$CHIQISH_MAX = 60000    # bulutdagi chegara bilan bir xil

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Yoz($matn) {
  $q = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $matn
  Write-Host $q
  try { Add-Content -Path $LOG -Value $q -Encoding UTF8 } catch { }
}

function HolatYoz($holat) {
  try {
    $s = @(
      ("vaqt=" + [DateTimeOffset]::Now.ToUnixTimeMilliseconds()),
      ("holat=" + $holat)
    )
    Set-Content -Path $HOLAT -Value $s -Encoding UTF8
  } catch { }
}

# Buyruqni alohida PowerShell jarayonida bajaradi. Alohida jarayon
# tanlandi, chunki: (1) vaqt chegarasini qo'yish mumkin, (2) buyruq
# qulab tushsa yordamchining o'zi o'lmaydi, (3) chiqishni to'liq
# (xatolari bilan) yig'ib olish oson.
function Bajar($buyruq) {
  $tasodif = [guid]::NewGuid().ToString("N")
  $skript = Join-Path $env:TEMP ("yrd_" + $tasodif + ".ps1")
  $soFayl = Join-Path $env:TEMP ("yrd_" + $tasodif + "_o.txt")
  $seFayl = Join-Path $env:TEMP ("yrd_" + $tasodif + "_e.txt")
  $bosh = '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8' + [Environment]::NewLine +
          '$ErrorActionPreference = "Continue"' + [Environment]::NewLine
  Set-Content -Path $skript -Value ($bosh + $buyruq) -Encoding UTF8
  $kod = -1
  try {
    $p = Start-Process powershell `
      -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $skript `
      -NoNewWindow -PassThru -RedirectStandardOutput $soFayl -RedirectStandardError $seFayl
    if (-not $p.WaitForExit($VaqtChegarasiDaqiqa * 60 * 1000)) {
      try { $p.Kill() } catch { }
      $kod = -2
    } else {
      $kod = $p.ExitCode
    }
  } catch {
    return @{ kod = -3; chiqish = "ishga tushirib bo'lmadi: " + $_.Exception.Message }
  }
  $chiqish = ""
  foreach ($f in @($soFayl, $seFayl)) {
    try {
      if (Test-Path $f) {
        $m = Get-Content $f -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if ($m) { $chiqish += $m }
      }
    } catch { }
  }
  foreach ($f in @($skript, $soFayl, $seFayl)) {
    try { Remove-Item $f -Force -ErrorAction SilentlyContinue } catch { }
  }
  if ($kod -eq -2) { $chiqish = "VAQT TUGADI (" + $VaqtChegarasiDaqiqa + " daqiqa) -- to'xtatildi.`r`n" + $chiqish }
  if ($chiqish.Length -gt $CHIQISH_MAX) {
    $chiqish = $chiqish.Substring(0, $CHIQISH_MAX) + "`r`n... (qisqartirildi)"
  }
  return @{ kod = $kod; chiqish = $chiqish }
}

Yoz "=== Monoblok yordamchisi ishga tushdi ==="
HolatYoz "ishga tushdi"

$natija = $null
while ($true) {
  try {
    $sorov = @{ key = $Key; wait = $true }
    if ($natija) { $sorov.natija = $natija }
    $tana = [System.Text.Encoding]::UTF8.GetBytes(($sorov | ConvertTo-Json -Compress -Depth 5))
    $javobRaw = Invoke-WebRequest -Uri $ENDPOINT -Method Post `
      -ContentType "application/json; charset=utf-8" -Body $tana -TimeoutSec $TIMEOUT -UseBasicParsing
    $javob = ([System.Text.Encoding]::UTF8.GetString($javobRaw.RawContentStream.ToArray())) | ConvertFrom-Json
    $natija = $null

    if (-not $javob.ok) {
      Yoz ("XATO (bulut): " + [string]$javob.error)
      HolatYoz "bulut rad etdi"
      Start-Sleep -Seconds 5
    } elseif ($javob.ish) {
      $ish = $javob.ish
      if (Test-Path $STOP) {
        Yoz ("RAD ETILDI (yordamchi_STOP.txt bor): " + [string]$ish.buyruq)
        $natija = @{ id = $ish.id; kod = -9; chiqish = "Yordamchi TO'XTATILGAN (yordamchi_STOP.txt)." }
        HolatYoz "to'xtatilgan"
      } else {
        Yoz ("TOPSHIRIQ: " + [string]$ish.buyruq)
        HolatYoz "bajaryapti"
        $t = Get-Date
        $n = Bajar ([string]$ish.buyruq)
        $sek = [int]((Get-Date) - $t).TotalSeconds
        $natija = @{ id = $ish.id; kod = $n.kod; chiqish = $n.chiqish }
        Yoz ("  -> kod " + $n.kod + ", " + $sek + " soniya, " + $n.chiqish.Length + " belgi")
      }
    } else {
      HolatYoz "ishlayapti"
    }
  } catch {
    Yoz ("XATO (internet): " + $_.Exception.Message)
    HolatYoz "internet yo'q"
    Start-Sleep -Seconds 5
  }
  Start-Sleep -Seconds $INTERVAL
}
