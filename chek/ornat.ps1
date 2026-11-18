# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTINI O'RNATUVCHI
#  Monoblokda BIR MARTA ishga tushiriladi. Hammasini o'zi qiladi:
#    1. Agent va ekran ko'rsatkichini saytdan yuklab oladi
#    2. Eski (qotib qolgan) nusxalarni to'xtatadi, eski avtozapuskni o'chiradi
#    3. O'zini tiklaydigan, oyna ko'rsatmaydigan ishga tushirgich yozadi
#    4. Avtozagruzkaga qo'yadi va darhol ishga tushiradi
#    5. Tekshiradi va natijani ekranga chiqaradi
#
#  Ishlatish (monoblokda, PowerShell'da bitta qator):
#    powershell -NoProfile -ExecutionPolicy Bypass -File "$home\ornat.ps1" -Key <kalit>
#
#  --- NEGA SHUNDAY QURILGAN --------------------------------------------
#  OYNASIZ (2026-11-18): agent oddiy PowerShell oynasida turardi va bir
#  kuni jimgina to'xtab qoldi. Sabab topildi: konsol oynasiga sichqoncha
#  bilan bosilsa Windows "matn tanlash" rejimiga o'tib BUTUN DASTURNI
#  muzlatib qo'yadi -- jarayon tirik ko'rinadi, lekin hech narsa qilmaydi.
#  O'sha kuni 6 ta chek shu sababli 37 daqiqa navbatda yotdi. Endi oyna
#  umuman yo'q, bosadigan joyi ham qolmadi.
#
#  VAZIFA EMAS, AVTOZAGRUZKA (2026-11-18): avval Scheduled Task qilingan
#  edi, lekin monoblokda administrator huquqi yo'q -- "Отказано в доступе"
#  xatosi chiqdi. Shuning uchun ikki narsa birlashtirildi:
#    - ishga tushirgich O'ZI HALQA ichida turadi: dastur o'lsa 5 soniyada
#      qaytadan ishga tushiradi (vazifadagi "qayta urinish" o'rniga);
#    - fayl Автозагрузка papkasiga qo'yiladi: monoblok o'chib yonsa
#      o'zi chiqadi. Ikkalasiga ham admin huquqi KERAK EMAS.
# ============================================================
param(
  [Parameter(Mandatory = $true)][string]$Key,
  [string]$PrinterName = "XP-Q80A"
)

$BAZA = "https://zagotovka.olimpgarden.uz/chek"
$AVTO = [Environment]::GetFolderPath('Startup')
$BIZNIKI = @("OlimpChekAgent.vbs", "OlimpChekEkran.vbs")

function Qadam($n, $matn) { Write-Host ("[" + $n + "/5] " + $matn) -ForegroundColor Cyan }
function Yaxshi($matn)    { Write-Host ("      " + $matn) -ForegroundColor Green }
function Yomon($matn)     { Write-Host ("      " + $matn) -ForegroundColor Red }
function Eslat($matn)     { Write-Host ("      " + $matn) -ForegroundColor Yellow }

Write-Host ""
Write-Host "  CHEK AGENTI -- O'RNATISH" -ForegroundColor White
Write-Host "  ------------------------" -ForegroundColor DarkGray

# --- 1. Yuklab olish -------------------------------------------------------
Qadam 1 "Fayllar yuklab olinmoqda..."
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
foreach ($f in @(@("chek_agent.ps1", "chek.ps1"), @("chek_ekran.ps1", "chek_ekran.ps1"))) {
  $manzil = $BAZA + "/" + $f[0] + "?v=" + (Get-Date -Format "yyyyMMddHHmmss")
  $joy = Join-Path $home $f[1]
  try {
    Invoke-WebRequest $manzil -OutFile $joy -UseBasicParsing -ErrorAction Stop
    Yaxshi ($f[1] + "  (" + [int]((Get-Item $joy).Length / 1024) + " KB)")
  } catch {
    Yomon ("yuklab bo'lmadi: " + $f[0] + " -- " + $_.Exception.Message)
    Yomon "Internetni tekshiring va qaytadan urinib ko'ring."
    exit 1
  }
}

# --- 2. Eskilarini to'xtatish ----------------------------------------------
Qadam 2 "Eski nusxalar to'xtatilmoqda..."
$toxtadi = 0
foreach ($nom in @("powershell.exe", "wscript.exe")) {
  try {
    Get-WmiObject Win32_Process -Filter ("Name='" + $nom + "'") |
      Where-Object {
        $_.ProcessId -ne $PID -and $_.CommandLine -like '*chek*' -and $_.CommandLine -notlike '*ornat.ps1*'
      } |
      ForEach-Object {
        $toxtadi++
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { }
      }
  } catch { }
}
if ($toxtadi -gt 0) { Yaxshi ("$toxtadi ta eski nusxa to'xtatildi") } else { Yaxshi "eski nusxa topilmadi" }

# Eski avtozapusk qoldiqlari. Qolib ketsa monoblok yonganda IKKITA agent
# ishga tushadi va har chek ikki marta chiqadi -- shuning uchun nomi
# o'zgartirib qo'yiladi (o'chirilmaydi, kerak bo'lsa qaytarish mumkin).
$eski = 0
try {
  $sh = New-Object -ComObject WScript.Shell
  Get-ChildItem $AVTO -File -ErrorAction SilentlyContinue | ForEach-Object {
    if ($BIZNIKI -contains $_.Name) { return }
    $tegishli = $false
    if (@(".bat", ".cmd", ".vbs", ".ps1") -contains $_.Extension.ToLower()) {
      try { if ((Get-Content $_.FullName -Raw -ErrorAction Stop) -match "chek") { $tegishli = $true } } catch { }
    } elseif ($_.Extension.ToLower() -eq ".lnk") {
      try {
        $y = $sh.CreateShortcut($_.FullName)
        if (("" + $y.TargetPath + " " + $y.Arguments) -match "chek") { $tegishli = $true }
      } catch { }
    }
    if ($tegishli) {
      try { Rename-Item $_.FullName ($_.Name + ".eski") -Force -ErrorAction Stop; $eski++ } catch { }
    }
  }
} catch { }
if ($eski -gt 0) { Eslat ("$eski ta eski avtozapusk o'chirildi (ikki marta chiqmasligi uchun)") }

# --- 3. O'zini tiklaydigan oynasiz ishga tushirgich ------------------------
Qadam 3 "Ishga tushirgichlar yozilmoqda..."
function VbsYoz($fayl, $buyruq, $izoh) {
  # Halqa: dastur qanday sabab bilan to'xtasa ham 5 soniyada qaytadan
  # ishga tushadi. `0` -- oyna ko'rsatilmasin, `True` -- tugashini kut.
  # DIQQAT: qatorlar MASSIV sifatida beriladi. Avval `-join` bilan bitta
  # matn qilingan edi -- natijada hamma qator bir-biriga yopishib, VBS
  # buzilgan chiqdi (sinovda tutildi). Set-Content massivning har
  # elementini alohida qatorga yozadi, qo'lda satr belgisi qo'yish shart emas.
  # DIQQAT: qo'shish amali ishlatilgan elementlar QAVS ichida bo'lishi SHART.
  # PowerShell'da vergul `+` dan kuchliroq bog'lanadi, ya'ni qavssiz yozilsa
  # butun ro'yxat bitta matnga qo'shilib ketadi va VBS bir qatorga yopishib
  # buziladi. Sinovda aynan shu tutildi (satrlar.Count = 7 o'rniga 1 edi).
  $satrlar = @(
    ("' " + $izoh),
    "' Avtomat yozilgan (ornat.ps1). Qo'lda tahrirlamang.",
    'Set sh = CreateObject("WScript.Shell")',
    'Do',
    ('  sh.Run "' + $buyruq.Replace('"', '""') + '", 0, True'),
    '  WScript.Sleep 5000',
    'Loop'
  )
  Set-Content -Path (Join-Path $AVTO $fayl) -Value $satrlar -Encoding ASCII
}
try {
  VbsYoz $BIZNIKI[0] `
    ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $home + '\chek.ps1" -Key ' + $Key + ' -PrinterName "' + $PrinterName + '"') `
    "Olimp zagotovka -- chek agenti"
  VbsYoz $BIZNIKI[1] `
    ('powershell -NoProfile -ExecutionPolicy Bypass -File "' + $home + '\chek_ekran.ps1"') `
    "Olimp zagotovka -- ekrandagi ko'rsatkich"
  Yaxshi ("Автозагрузка papkasiga yozildi (admin huquqi kerak emas)")
} catch {
  Yomon ("yozib bo'lmadi: " + $_.Exception.Message)
  exit 1
}

# --- 4. Darhol ishga tushirish ---------------------------------------------
Qadam 4 "Ishga tushirilmoqda..."
foreach ($v in $BIZNIKI) {
  try {
    Start-Process "wscript.exe" -ArgumentList ('"' + (Join-Path $AVTO $v) + '"') -WindowStyle Hidden
    Yaxshi $v
  } catch {
    Yomon ($v + " -- " + $_.Exception.Message)
  }
}

# --- 5. Tekshirish ---------------------------------------------------------
Qadam 5 "Tekshirilmoqda (20 soniya)..."
$holatFayl = Join-Path $home "chek_holat.txt"
try { Remove-Item $holatFayl -Force -ErrorAction SilentlyContinue } catch { }
$tirik = $false
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Seconds 1
  if (Test-Path $holatFayl) { $tirik = $true; break }
}

Write-Host ""
if ($tirik) {
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host "   HAMMASI JOYIDA -- agent ishlayapti" -ForegroundColor Green
  Write-Host "  ============================================" -ForegroundColor Green
  Write-Host ""
  foreach ($q in (Get-Content $holatFayl -Encoding UTF8)) { Write-Host ("  " + $q) -ForegroundColor Gray }
  Write-Host ""
  Write-Host "  Ekranning o'ng pastki burchagida KO'K yozuvli oyna" -ForegroundColor Gray
  Write-Host "  turgan bo'lishi kerak. Monoblok o'chib yonsa ham o'zi" -ForegroundColor Gray
  Write-Host "  chiqadi, dastur o'lsa 5 soniyada o'zi tiklanadi." -ForegroundColor Gray
} else {
  Write-Host "  ============================================" -ForegroundColor Red
  Write-Host "   AGENT ISHGA TUSHMADI" -ForegroundColor Red
  Write-Host "  ============================================" -ForegroundColor Red
  Write-Host "  chek_holat.txt yaratilmadi. Quyidagi logni ko'ring." -ForegroundColor Gray
}
Write-Host ""
Write-Host "  --- chek_log.txt (oxirgi 10 qator) ---" -ForegroundColor DarkGray
if (Test-Path (Join-Path $home "chek_log.txt")) {
  Get-Content (Join-Path $home "chek_log.txt") -Tail 10 | ForEach-Object { Write-Host ("  " + $_) }
} else {
  Write-Host "  (log fayl hali yo'q)" -ForegroundColor DarkGray
}
Write-Host ""
