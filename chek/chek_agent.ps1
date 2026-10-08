# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTI  (USB printer uchun)
#  Telegramda "Tayyor" bosilganda zayavka ro'yxatini chek printerida chiqaradi.
#  Printer monoblokka USB bilan ulangan -- IP manzil KERAK EMAS.
#
#  SINOV.bat        - chek ko'rinishi (printerga yuborilmaydi)
#  PRINTERLAR.bat   - o'rnatilgan printerlar ro'yxati
#  ISHGA_TUSHIRISH.bat - ishga tushirish
# ============================================================
param(
  [string]$PrinterName = "",
  [string]$Key = "",
  [switch]$Test,
  [switch]$ListPrinters
)

$ENDPOINT = "https://zagotovka-zayavka-send.olimpzagotovka.workers.dev/print/poll"
$INTERVAL = 4
$LOG      = Join-Path $PSScriptRoot "chek_log.txt"
$KENGLIK  = 48   # Xprinter Q80A -- 80 mm qogoz = 48 belgi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Yoz($matn) {
  $qator = "{0}  {1}" -f (Get-Date -Format "dd.MM HH:mm:ss"), $matn
  Write-Host $qator
  try { Add-Content -Path $LOG -Value $qator -Encoding UTF8 } catch {}
}

# --- RAW chop etish: ESC/POS baytlarini to'g'ridan-to'g'ri printerga ---
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class RawPrint {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DOCINFO { [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
                          [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
                          [MarshalAs(UnmanagedType.LPWStr)] public string pDataType; }
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool OpenPrinter(string src, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool StartDocPrinter(IntPtr hPrinter, int level, ref DOCINFO di);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.drv", SetLastError=true)]
  public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

  public static string Send(string printer, byte[] data) {
    IntPtr h = IntPtr.Zero;
    if (!OpenPrinter(printer, out h, IntPtr.Zero)) return "printer ochilmadi (OpenPrinter)";
    try {
      DOCINFO di = new DOCINFO();
      di.pDocName = "Zayavka chek"; di.pDataType = "RAW";
      if (!StartDocPrinter(h, 1, ref di)) return "StartDocPrinter xato";
      if (!StartPagePrinter(h)) { EndDocPrinter(h); return "StartPagePrinter xato"; }
      IntPtr buf = Marshal.AllocCoTaskMem(data.Length);
      Marshal.Copy(data, 0, buf, data.Length);
      int yozildi = 0;
      bool ok = WritePrinter(h, buf, data.Length, out yozildi);
      Marshal.FreeCoTaskMem(buf);
      EndPagePrinter(h); EndDocPrinter(h);
      if (!ok) return "WritePrinter xato";
      return "";
    } finally { ClosePrinter(h); }
  }
}
"@

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
    if ($nom.Length -gt ($KENGLIK - $son.Length - 1)) { $nom = $nom.Substring(0, $KENGLIK - $son.Length - 1) }
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

function PrinterTop {
  $hammasi = @(Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue)
  if ($hammasi.Count -eq 0) { return $null }
  if (-not [string]::IsNullOrWhiteSpace($PrinterName)) {
    $t = @($hammasi | Where-Object { $_.Name -eq $PrinterName })
    if ($t.Count -gt 0) { return $t[0].Name }
    $t = @($hammasi | Where-Object { $_.Name -like "*$PrinterName*" })
    if ($t.Count -gt 0) { return $t[0].Name }
    return $null
  }
  $t = @($hammasi | Where-Object { $_.Name -match "XP-|Xprinter|POS|Thermal|Receipt|58|80mm" })
  if ($t.Count -gt 0) { return $t[0].Name }
  $t = @($hammasi | Where-Object { $_.Default -eq $true })
  if ($t.Count -gt 0) { return $t[0].Name }
  return $hammasi[0].Name
}

if ($ListPrinters) {
  Write-Host "O'rnatilgan printerlar:"
  Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue | ForEach-Object {
    $bel = if ($_.Default) { "[standart]" } else { "          " }
    Write-Host ("   {0} {1}    port: {2}" -f $bel, $_.Name, $_.PortName)
  }
  Write-Host ""
  Write-Host ("Avtomatik tanlanadigan printer: " + (PrinterTop))
  exit 0
}

if ($Test) {
  $namuna = [pscustomobject]@{
    source = "MANGAL"; dest = "OLIMP 1: Mangal sklad"; login = "Hosil"; when = "08.10.2026"
    items  = @(
      [pscustomobject]@{ name = "Ijjon shashlik (sht)"; num = 200 },
      [pscustomobject]@{ name = "Kuskovoy mol (sht)";   num = 90 },
      [pscustomobject]@{ name = "Gijduvon 100gr (sht)"; num = 60 }
    )
  }
  Write-Host ("=" * 34)
  foreach ($qator in (ChekQatorlar $namuna)) { Write-Host ("|" + $qator.PadRight($KENGLIK) + "|") }
  Write-Host ("=" * 34)
  Write-Host ""
  Write-Host ("Topilgan printer: " + (PrinterTop))
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Key)) {
  Write-Host "XATO: kalit berilmagan." -ForegroundColor Red
  exit 1
}

$PRINTER = PrinterTop
if (-not $PRINTER) {
  Yoz "XATO: bu kompyuterda birorta printer topilmadi."
  exit 1
}
Yoz "=== Chek agenti ishga tushdi. Printer: $PRINTER ==="

$bajarildi = @()
while ($true) {
  try {
    $sorov = @{ key = $Key }
    if ($bajarildi.Count -gt 0) { $sorov.done = $bajarildi }
    $tana = $sorov | ConvertTo-Json -Compress
    $baytlar = [System.Text.Encoding]::UTF8.GetBytes($tana)
    # 2026-10-08: javob MAJBURIY UTF-8 deb o'qiladi. Invoke-RestMethod
    # (PowerShell 5.1) charset ko'rsatilmasa ISO-8859-1 deb o'qib, kirill
    # harflarni buzadi -- chekda "???" bo'lib chiqqandi.
    $javobRaw = Invoke-WebRequest -Uri $ENDPOINT -Method Post -ContentType "application/json; charset=utf-8" -Body $baytlar -TimeoutSec 20 -UseBasicParsing
    $matnJson = [System.Text.Encoding]::UTF8.GetString($javobRaw.RawContentStream.ToArray())
    $javob = $matnJson | ConvertFrom-Json
    $bajarildi = @()

    if ($javob.ok -and $javob.jobs) {
      foreach ($ish in $javob.jobs) {
        $matn = ChekMatni $ish
        $data = [System.Text.Encoding]::GetEncoding(866).GetBytes($matn)
        $xato = [RawPrint]::Send($PRINTER, $data)
        if ($xato -eq "") {
          $bajarildi += $ish.id
          Yoz ("CHEK CHIQDI  {0} -> {1}  ({2} band)" -f $ish.source, $ish.dest, @($ish.items).Count)
        } else {
          Yoz ("XATO (printer): " + $xato)
          break
        }
      }
    }
  } catch {
    Yoz ("XATO (internet): " + $_.Exception.Message)
  }
  Start-Sleep -Seconds $INTERVAL
}
