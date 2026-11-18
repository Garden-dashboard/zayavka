# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTINI O'RNATUVCHI
#  Monoblokda BIR MARTA ishga tushiriladi. Hammasini o'zi qiladi:
#    1. Agent va ekran ko'rsatkichini saytdan yuklab oladi
#    2. Eski (qotib qolgan) nusxalarni to'xtatadi
#    3. Oyna ko'rsatmaydigan ishga tushirgichlarni yozadi
#    4. Ikkita avtomat vazifa qilib ro'yxatga oladi -- monoblok o'chib
#       yonsa ham, dastur o'lsa ham o'zi tiklanadi
#    5. Ishga tushiradi va natijani ekranga chiqaradi
#
#  Ishlatish (monoblokda, PowerShell'da bitta qator):
#    powershell -NoProfile -ExecutionPolicy Bypass -File "$home\ornat.ps1" -Key <kalit>
#
#  NEGA OYNASIZ (2026-11-18): agent oddiy PowerShell oynasida turardi va
#  bir kuni jimgina to'xtab qoldi -- oyna ichiga sichqoncha bilan bosilsa
#  Windows konsoli "matn tanlash" rejimiga o'tib butun dasturni to'xtatib
#  qo'yadi. Jarayon tirik ko'rinadi, lekin hech narsa qilmaydi. Endi
#  oyna umuman yo'q, shuning uchun bu takrorlanmaydi.
# ============================================================
param(
  [Parameter(Mandatory = $true)][string]$Key,
  [string]$PrinterName = "XP-Q80A"
)

$ErrorActionPreference = "Stop"
$BAZA = "https://zagotovka.olimpgarden.uz/chek"

function Qadam($n, $matn) { Write-Host ("[" + $n + "/5] " + $matn) -ForegroundColor Cyan }
function Yaxshi($matn)    { Write-Host ("      " + $matn) -ForegroundColor Green }
function Yomon($matn)     { Write-Host ("      " + $matn) -ForegroundColor Red }

Write-Host ""
Write-Host "  CHEK AGENTI -- O'RNATISH" -ForegroundColor White
Write-Host "  ------------------------" -ForegroundColor DarkGray

# --- 1. Yuklab olish -------------------------------------------------------
Qadam 1 "Fayllar yuklab olinmoqda..."
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }
foreach ($f in @(@("chek_agent.ps1", "chek.ps1"), @("chek_ekran.ps1", "chek_ekran.ps1"))) {
  $manzil = $BAZA + "/" + $f[0] + "?v=" + (Get-Date -Format "yyyyMMddHHmmss")
  $joy = Join-Path $home $f[1]
  try {
    Invoke-WebRequest $manzil -OutFile $joy -UseBasicParsing
    Yaxshi ($f[1] + "  (" + [int]((Get-Item $joy).Length / 1024) + " KB)")
  } catch {
    Yomon ("yuklab bo'lmadi: " + $f[0] + " -- " + $_.Exception.Message)
    Yomon "Internetni tekshiring va qaytadan urinib ko'ring."
    exit 1
  }
}

# --- 2. Eskilarini to'xtatish ---------------------------------------------
Qadam 2 "Eski nusxalar to'xtatilmoqda..."
$oz = $PID
$topildi = 0
try {
  Get-WmiObject Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.ProcessId -ne $oz -and $_.CommandLine -like '*chek*.ps1*' -and $_.CommandLine -notlike '*ornat.ps1*' } |
    ForEach-Object {
      $topildi++
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
    }
} catch { }
# Faqat BIZNING ishga tushirgichlarimiz. Monoblokda boshqa vbs vazifalar
# bo'lishi mumkin -- ularga tegmaymiz.
try {
  Get-WmiObject Win32_Process -Filter "Name='wscript.exe'" |
    Where-Object { $_.CommandLine -like '*chek*' } |
    ForEach-Object {
      $topildi++
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
    }
} catch { }
if ($topildi -gt 0) { Yaxshi ("$topildi ta eski nusxa to'xtatildi") } else { Yaxshi "eski nusxa topilmadi" }

# --- 3. Oynasiz ishga tushirgichlar ---------------------------------------
Qadam 3 "Oyna ko'rsatmaydigan ishga tushirgichlar yozilmoqda..."
function VbsYoz($fayl, $buyruq) {
  $matn = 'Set sh = CreateObject("WScript.Shell")' + "`r`n" +
          'sh.Run "' + $buyruq.Replace('"', '""') + '", 0, True'
  Set-Content -Path (Join-Path $home $fayl) -Value $matn -Encoding ASCII
}
VbsYoz "chek_hidden.vbs" ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $home + '\chek.ps1" -Key ' + $Key + ' -PrinterName "' + $PrinterName + '"')
VbsYoz "chek_ekran.vbs"  ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $home + '\chek_ekran.ps1"')
Yaxshi "chek_hidden.vbs, chek_ekran.vbs"

# --- 4. Avtomat vazifalar --------------------------------------------------
Qadam 4 "Avtomat vazifalar ro'yxatga olinmoqda..."
# AtLogOn  -- monoblok o'chib yonsa o'zi chiqadi
# Har 5 daqiqa + IgnoreNew -- dastur o'lsa 5 daqiqada o'zi tiklanadi,
#                             tirik bo'lsa ikkinchi nusxa ochilmaydi
$p  = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$s  = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$t1 = New-ScheduledTaskTrigger -AtLogOn
$t2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
foreach ($v in @(@("OlimpChekAgent", "chek_hidden.vbs"), @("OlimpChekEkran", "chek_ekran.vbs"))) {
  try {
    $a = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ('"' + $home + '\' + $v[1] + '"')
    Register-ScheduledTask -TaskName $v[0] -Action $a -Trigger $t1, $t2 -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName $v[0]
    Yaxshi ($v[0] + " -- ro'yxatga olindi va ishga tushirildi")
  } catch {
    Yomon ($v[0] + " -- XATO: " + $_.Exception.Message)
  }
}

# --- 5. Tekshirish ---------------------------------------------------------
Qadam 5 "Tekshirilmoqda (15 soniya)..."
$holatFayl = Join-Path $home "chek_holat.txt"
$tirik = $false
for ($i = 0; $i -lt 15; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $holatFayl) { $tirik = $true; break }
}

Write-Host ""
if ($tirik) {
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host "   HAMMASI JOYIDA -- agent ishlayapti" -ForegroundColor Green
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host ""
  Write-Host "  Ekranning o'ng pastki burchagida KO'K yozuvli oyna" -ForegroundColor Gray
  Write-Host "  paydo bo'lishi kerak. Navbatda turgan cheklar bo'lsa" -ForegroundColor Gray
  Write-Host "  printerdan hozir chiqadi." -ForegroundColor Gray
} else {
  Write-Host "  ============================================" -ForegroundColor Red
  Write-Host "   AGENT ISHGA TUSHMADI" -ForegroundColor Red
  Write-Host "  ============================================" -ForegroundColor Red
  Write-Host "  chek_holat.txt yaratilmadi. Quyidagi logni ko'ring." -ForegroundColor Gray
}
Write-Host ""
Write-Host "  --- chek_log.txt (oxirgi 12 qator) ---" -ForegroundColor DarkGray
if (Test-Path (Join-Path $home "chek_log.txt")) {
  Get-Content (Join-Path $home "chek_log.txt") -Tail 12 | ForEach-Object { Write-Host ("  " + $_) }
} else {
  Write-Host "  (log fayl hali yo'q)" -ForegroundColor DarkGray
}
Write-Host ""
