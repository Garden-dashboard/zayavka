# ============================================================
#  OLIMP ZAGOTOVKA - CHEK AGENTI KO'RSATKICHI
#  Monoblok ekranining burchagida turadigan kichik belgi. Chek agenti
#  ishlayotganini bir qarashda ko'rsatadi -- hech qayerga kirish,
#  hech narsa ochish shart emas.
#
#  2026-11-18, egasi so'rovi: "menga monobloq ekranida turishi kerak,
#  shu yerdan bilaman ishlayapdimi yoki yo'q; monobloq o'chib yonsa ham
#  avtomat ekranda kichkina qilib turishi kerak, ishlayapdi deb ko'k
#  yozuvda". Sabab: agent bir marta jimgina to'xtab qolgan va buni hech
#  kim bilmagan -- cheklar navbatda to'planib qolavergan.
#
#  2026-11-18 (ikkinchi so'rov): "bu juda katta ku, ekranni ko'rsatmay
#  qo'yadi". Shuning uchun IKKI O'LCHAM qilindi:
#    - hammasi joyida bo'lsa  -> kichkina belgi, yarim shaffof, xalaqit
#      bermaydi (ustiga sichqoncha olib borilsa tafsiloti chiqadi);
#    - muammo bo'lsa          -> o'zi kattalashadi, to'liq ko'rinadi va
#      sababini yozadi. Ya'ni ko'zga faqat KERAK bo'lganda tashlanadi.
#
#  QANDAY BILADI: agent har aylanishda `chek_holat.txt` faylini
#  yangilab turadi. Ko'rsatkich har 2 soniyada shu faylga qaraydi:
#    - fayl yangi (45 soniyadan yosh) + holat yaxshi -> KO'K
#    - fayl yangi, lekin printerda muammo bor        -> SARIQ, sababi
#    - fayl eskirgan yoki yo'q                       -> QIZIL
#  Ya'ni "jarayon bormi" emas, "agent ROSTDAN aylanayaptimi" tekshiriladi.
#  (Agent bir marta MUZLAB qolgan edi: jarayon tirik, lekin ishlamaydi.)
#
#  Belgini sichqoncha bilan tutib ko'chirish mumkin -- joyi eslab qolinadi.
#  -Soniya <n>  : sinov uchun, n soniyadan keyin o'zi yopiladi.
# ============================================================
param(
  [int]$Soniya = 0,
  [string]$Fayl = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$HOLAT    = if ($Fayl -ne "") { $Fayl } else { Join-Path $PSScriptRoot "chek_holat.txt" }
$JOY      = Join-Path $PSScriptRoot "chek_ekran_joy.txt"
$ESKIRISH = 45   # soniya: holat fayli shundan eski bo'lsa agent o'lgan hisoblanadi

$KOK     = [System.Drawing.Color]::FromArgb(21, 101, 192)
$QIZIL   = [System.Drawing.Color]::FromArgb(198, 40, 40)
$SARIQ   = [System.Drawing.Color]::FromArgb(230, 120, 0)
$KULRANG = [System.Drawing.Color]::FromArgb(110, 110, 110)
$NUQTA   = [string][char]0x25CF

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.TopMost         = $true
$form.ShowInTaskbar   = $false
$form.BackColor       = [System.Drawing.Color]::White
$form.StartPosition   = 'Manual'
$form.Size            = New-Object System.Drawing.Size(104, 24)

$form.Add_Paint({
  param($s, $e)
  $qalam = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(200, 200, 200)), 1
  $e.Graphics.DrawRectangle($qalam, 0, 0, $s.Width - 1, $s.Height - 1)
  $qalam.Dispose()
})

$asosiy = New-Object System.Windows.Forms.Label
$asosiy.ForeColor = $KULRANG
$form.Controls.Add($asosiy)

$past = New-Object System.Windows.Forms.Label
$past.ForeColor = $KULRANG
$past.Visible   = $false
$form.Controls.Add($past)

$maslahat = New-Object System.Windows.Forms.ToolTip
$maslahat.InitialDelay = 200

# --- Ikki o'lcham. O'ng pastki burchak qimirlamasin: oyna kattalashganda
#     chapga va yuqoriga o'sadi, shuning uchun eski chekka saqlanadi. ---
$script:rejim = ""
function Olcham($katta) {
  if ($script:rejim -eq $katta) { return }
  $script:rejim = $katta
  $ong = $form.Left + $form.Width
  $tag = $form.Top + $form.Height
  if ($katta -eq "katta") {
    $form.Size        = New-Object System.Drawing.Size(272, 56)
    $form.Opacity     = 1.0
    $asosiy.Font      = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $asosiy.Location  = New-Object System.Drawing.Point(12, 7)
    $asosiy.Size      = New-Object System.Drawing.Size(248, 21)
    $past.Font        = New-Object System.Drawing.Font("Segoe UI", 8)
    $past.Location    = New-Object System.Drawing.Point(13, 30)
    $past.Size        = New-Object System.Drawing.Size(248, 18)
    $past.Visible     = $true
  } else {
    $form.Size        = New-Object System.Drawing.Size(104, 24)
    $form.Opacity     = 0.78
    $asosiy.Font      = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
    $asosiy.Location  = New-Object System.Drawing.Point(8, 4)
    $asosiy.Size      = New-Object System.Drawing.Size(92, 16)
    $past.Visible     = $false
  }
  # Ekrandan chiqib ketmasin
  $ish = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $x = [Math]::Max($ish.Left, [Math]::Min($ong - $form.Width, $ish.Right - $form.Width))
  $y = [Math]::Max($ish.Top, [Math]::Min($tag - $form.Height, $ish.Bottom - $form.Height))
  $form.Location = New-Object System.Drawing.Point([int]$x, [int]$y)
}

# --- Boshlang'ich joy: eslab qolingan joy, bo'lmasa o'ng pastki burchak ---
$ish = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$x = $ish.Right - $form.Width - 14
$y = $ish.Bottom - $form.Height - 14
try {
  if (Test-Path $JOY) {
    $b = (Get-Content $JOY -ErrorAction Stop) -split ','
    if ($b.Count -eq 2) {
      $bx = [int]$b[0]; $by = [int]$b[1]
      if ($bx -ge $ish.Left -and $by -ge $ish.Top -and
          $bx -le ($ish.Right - 40) -and $by -le ($ish.Bottom - 20)) { $x = $bx; $y = $by }
    }
  }
} catch { }
$form.Location = New-Object System.Drawing.Point($x, $y)
Olcham "kichik"

function HolatOqi {
  $n = @{ vaqt = "0"; printer = ""; holat = ""; bugun = "0"; oxirgi = "" }
  try {
    if (-not (Test-Path $HOLAT)) { return $n }
    foreach ($q in (Get-Content $HOLAT -Encoding UTF8 -ErrorAction Stop)) {
      $p = $q.IndexOf("=")
      if ($p -gt 0) { $n[$q.Substring(0, $p)] = $q.Substring($p + 1) }
    }
  } catch { }
  return $n
}

$yangila = {
  $h = HolatOqi
  $yosh = [double]::MaxValue
  $bor = $false
  try {
    $v = [int64]$h.vaqt
    if ($v -gt 0) { $bor = $true; $yosh = ([DateTimeOffset]::Now.ToUnixTimeMilliseconds() - $v) / 1000.0 }
  } catch { }

  if ($yosh -gt $ESKIRISH) {
    # MUAMMO -- kattalashadi, ko'zga tashlanadi
    Olcham "katta"
    $asosiy.ForeColor = $QIZIL
    $asosiy.Text      = "$NUQTA Chek printeri ISHLAMAYAPTI"
    $past.ForeColor   = $QIZIL
    if ($bor) {
      $daq = [int]($yosh / 60)
      $past.Text = if ($daq -lt 1) { "agent to'xtadi -- bir daqiqadan beri jim" }
                   else { "agent to'xtagan -- $daq daqiqadan beri jim" }
    } else {
      $past.Text = "agent hali ishga tushmagan"
    }
    $maslahat.SetToolTip($asosiy, $past.Text)
  } elseif ($h.holat -ne "ishlayapti" -and $h.holat -ne "ishga tushdi") {
    Olcham "katta"
    $asosiy.ForeColor = $SARIQ
    $asosiy.Text      = "$NUQTA Chek printeri -- e'tibor bering"
    $past.ForeColor   = $SARIQ
    $past.Text        = [string]$h.holat
    $maslahat.SetToolTip($asosiy, $past.Text)
  } else {
    # HAMMASI JOYIDA -- kichkina belgi, xalaqit bermaydi
    Olcham "kichik"
    $asosiy.ForeColor = $KOK
    $asosiy.Text      = "$NUQTA chek"
    $t = "Chek printeri ishlayapti" + [Environment]::NewLine +
         "printer: " + $h.printer + [Environment]::NewLine +
         "bugun " + $h.bugun + " ta chek"
    if ($h.oxirgi -ne "") { $t = $t + [Environment]::NewLine + "oxirgi: " + $h.oxirgi }
    $maslahat.SetToolTip($asosiy, $t)
    $maslahat.SetToolTip($form, $t)
  }
}

$soat = New-Object System.Windows.Forms.Timer
$soat.Interval = 2000
$soat.Add_Tick($yangila)
$soat.Start()
& $yangila

# --- Sichqoncha bilan ko'chirish, joyi eslab qolinadi ---
$script:bosildi = $false
$script:dx = 0
$script:dy = 0
$bosish = {
  param($s, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    $mp = [System.Windows.Forms.Control]::MousePosition
    $script:bosildi = $true
    $script:dx = $mp.X - $form.Left
    $script:dy = $mp.Y - $form.Top
  }
}
$surish = {
  param($s, $e)
  if ($script:bosildi) {
    $mp = [System.Windows.Forms.Control]::MousePosition
    $form.Location = New-Object System.Drawing.Point(($mp.X - $script:dx), ($mp.Y - $script:dy))
  }
}
$qoyish = {
  param($s, $e)
  $script:bosildi = $false
  try { Set-Content -Path $JOY -Value ("" + $form.Left + "," + $form.Top) -Encoding ASCII } catch { }
}
foreach ($c in @($form, $asosiy, $past)) {
  $c.Add_MouseDown($bosish); $c.Add_MouseMove($surish); $c.Add_MouseUp($qoyish)
}

if ($Soniya -gt 0) {
  $yopgich = New-Object System.Windows.Forms.Timer
  $yopgich.Interval = $Soniya * 1000
  $yopgich.Add_Tick({ $yopgich.Stop(); $form.Close() })
  $yopgich.Start()
}

[System.Windows.Forms.Application]::Run($form)
