# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTI
#  Telegramda "Tayyor" bosilganda zayavka ro'yxatini Xprinter'ga chiqaradi.
#  Monoblokda fonda ishlaydi. Printer bilan BIR TARMOQDA bo'lsa kifoya.
#
#  Sinov:  powershell -ExecutionPolicy Bypass -File chek_agent.ps1 -Test
#          (printerga hech narsa yuborilmaydi, chek ekranga chiqadi)
# ============================================================
#  SOZLAMA: faqat quyidagi ikki qatorni to'g'rilang
# ------------------------------------------------------------
param(
  [string]$Ip   = "192.168.123.100",
  [string]$Port = "9100",
  [string]$Key  = "",
  [switch]$Test
)
$PRINTER_IP   = $Ip
$PRINTER_PORT = [int]$Port
# ------------------------------------------------------------

$ENDPOINT  = "https://zagotovka-zayavka-send.olimpzagotovka.workers.dev/print/poll"
if ([string]::IsNullOrWhiteSpace($Key)) {
  $kf = Join-Path $PSScriptRoot "chek_key.txt"
  if (Test-Path $kf) { $Key = (Get-Content $kf -Raw).Trim() }
}
$AGENT_KEY = $Key
$INTERVAL  = 4
$LOG       = Join-Path $PSScriptRoot "chek_log.txt"
$KENGLIK   = 32

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Yoz($matn) {
  $qator = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $matn
  Write-Host $qator
  try { Add-Content -Path $LOG -Value $qator -Encoding UTF8 } catch {}
}

# --- ESC/POS buyruqlari ---
$E = [char]27
$G = [char]29
$INIT      = $E + "@"
$CP866     = $E + "t" + [char]17
$MARKAZ    = $E + "a" + [char]1
$CHAP      = $E + "a" + [char]0
$QALIN_ON  = $E + "E" + [char]1
$QALIN_OFF = $E + "E" + [char]0
$KATTA     = $G + "!" + [char]17
$ODDIY     = $G + "!" + [char]0
$KES       = $G + "V" + [char]66 + [char]3

function ChekQatorlar($ish) {
  $chiziq = "-" * $KENGLIK
  $q = @()
  $q += "ZAYAVKA"
  $q += [string]$ish.source
  $q += $chiziq
  $q += "Kimga : " + [string]$ish.dest
  $q += "Yozgan: " + [string]$ish.login
  $q += "Sana  : " + [string]$ish.when
  $q += $chiziq
  foreach ($b in $ish.items) {
    $nom = [string]$b.name
    $son = [string]$b.num
    if ($nom.Length -gt ($KENGLIK - $son.Length - 1)) {
      $nom = $nom.Substring(0, $KENGLIK - $son.Length - 1)
    }
    $bosh = $KENGLIK - $nom.Length - $son.Length
    if ($bosh -lt 1) { $bosh = 1 }
    $q += $nom + (" " * $bosh) + $son
  }
  $q += $chiziq
  $q += "Jami: {0} band" -f @($ish.items).Count
  $q += "Chiqarildi: " + (Get-Date -Format "dd.MM.yyyy HH:mm")
  return $q
}

function ChekMatni($ish) {
  $q = ChekQatorlar $ish
  $s = $INIT + $CP866
  $s += $MARKAZ + $QALIN_ON + $KATTA + $q[0] + "`n" + $ODDIY
  $s += $q[1] + "`n" + $QALIN_OFF + $CHAP
  for ($i = 2; $i -lt $q.Count - 2; $i++) { $s += $q[$i] + "`n" }
  $s += $QALIN_ON + $q[$q.Count - 2] + "`n" + $QALIN_OFF
  $s += $q[$q.Count - 1] + "`n"
  $s += "`n`n`n" + $KES
  return $s
}

function Chop($matn) {
  $mijoz = New-Object System.Net.Sockets.TcpClient
  try {
    $ulanish = $mijoz.BeginConnect($PRINTER_IP, $PRINTER_PORT, $null, $null)
    if (-not $ulanish.AsyncWaitHandle.WaitOne(4000, $false)) { throw "printer javob bermadi (4 s)" }
    $mijoz.EndConnect($ulanish)
    $oqim = $mijoz.GetStream()
    $baytlar = [System.Text.Encoding]::GetEncoding(866).GetBytes($matn)
    $oqim.Write($baytlar, 0, $baytlar.Length)
    $oqim.Flush()
    Start-Sleep -Milliseconds 300
  } finally {
    $mijoz.Close()
  }
}

# --- SINOV REJIMI ---
if ($Test) {
  $namuna = [pscustomobject]@{
    source = "MANGAL"
    dest   = "OLIMP 1: Mangal sklad"
    login  = "Hosil"
    when   = "08.10.2026"
    items  = @(
      [pscustomobject]@{ name = "Ijjon shashlik (sht)"; num = 200 },
      [pscustomobject]@{ name = "Kuskovoy mol (sht)";   num = 90 },
      [pscustomobject]@{ name = "Gijduvon 100gr (sht)"; num = 60 },
      [pscustomobject]@{ name = "Krilishki marinad kg"; num = 17.2 }
    )
  }
  Write-Host ("=" * 34)
  foreach ($qator in (ChekQatorlar $namuna)) { Write-Host ("|" + $qator.PadRight($KENGLIK) + "|") }
  Write-Host ("=" * 34)
  Write-Host "Yuqoridagi ko'rinish chekda shunday chiqadi (32 belgi kenglikda)."
  exit 0
}

if ([string]::IsNullOrWhiteSpace($AGENT_KEY)) {
  Write-Host "XATO: kalit berilmagan. Ishga tushirish: .\chek_agent.ps1 -Key <kalit>" -ForegroundColor Red
  exit 1
}

Yoz "=== Chek agenti ishga tushdi. Printer: $PRINTER_IP port $PRINTER_PORT ==="
$bajarildi = @()

while ($true) {
  try {
    $sorov = @{ key = $AGENT_KEY }
    if ($bajarildi.Count -gt 0) { $sorov.done = $bajarildi }
    $tana = $sorov | ConvertTo-Json -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($tana)
    $javob = Invoke-RestMethod -Uri $ENDPOINT -Method Post -ContentType "application/json; charset=utf-8" -Body $baytlar -TimeoutSec 20
    $bajarildi = @()

    if ($javob.ok -and $javob.jobs) {
      foreach ($ish in $javob.jobs) {
        try {
          Chop (ChekMatni $ish)
          $bajarildi += $ish.id
          Yoz ("CHEK CHIQDI  {0} -> {1}  ({2} band)" -f $ish.source, $ish.dest, @($ish.items).Count)
        } catch {
          Yoz ("XATO (printer): " + $_.Exception.Message)
          break
        }
      }
    }
  } catch {
    Yoz ("XATO (internet): " + $_.Exception.Message)
  }
  Start-Sleep -Seconds $INTERVAL
}
