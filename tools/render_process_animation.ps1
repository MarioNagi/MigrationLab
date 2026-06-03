Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$diagramDir = Join-Path $repoRoot 'diagrams'
$frameDir = Join-Path $diagramDir 'frames'
New-Item -ItemType Directory -Force $diagramDir, $frameDir | Out-Null

function Brush([string]$Hex) {
    return New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Hex))
}
function PenObj([string]$Hex, [float]$Width = 1) {
    $p = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($Hex), $Width)
    $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $p.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    return $p
}
function FontObj([float]$Size, [string]$Style = 'Regular') {
    return New-Object System.Drawing.Font('Segoe UI', $Size, [System.Drawing.FontStyle]::$Style)
}
function Draw-RoundedRect($Gfx, [float]$X, [float]$Y, [float]$W, [float]$H, [float]$R, $Fill, $Border) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X+$W-$d, $Y, $d, $d, 270, 90)
    $path.AddArc($X+$W-$d, $Y+$H-$d, $d, $d, 0, 90)
    $path.AddArc($X, $Y+$H-$d, $d, $d, 90, 90)
    $path.CloseFigure()
    $Gfx.FillPath($Fill, $path)
    $Gfx.DrawPath($Border, $path)
    $path.Dispose()
}
function Draw-CenteredText($Gfx, [string]$Text, $Font, $Brush, [float]$X, [float]$Y, [float]$W, [float]$H) {
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $Gfx.DrawString($Text, $Font, $Brush, (New-Object System.Drawing.RectangleF($X,$Y,$W,$H)), $sf)
    $sf.Dispose()
}
function Draw-Node($Gfx, $Node, [bool]$Active) {
    $fill = if ($Active) { Brush '#dbeafe' } else { Brush '#ffffff' }
    $border = if ($Active) { PenObj '#2563eb' 4 } else { PenObj '#cbd5e1' 2 }
    Draw-RoundedRect $Gfx $Node.X $Node.Y $Node.W $Node.H 16 $fill $border
    Draw-CenteredText $Gfx $Node.Title (FontObj 20 Bold) (Brush '#0f172a') $Node.X ($Node.Y+10) $Node.W 32
    Draw-CenteredText $Gfx $Node.Sub (FontObj 13 Regular) (Brush '#475569') $Node.X ($Node.Y+48) $Node.W 28
}
function Draw-Arrow($Gfx, $A, $B, [bool]$Active, [float]$Progress) {
    $color = if ($Active) { '#2563eb' } else { '#cbd5e1' }
    $pen = PenObj $color 5
    $x1 = $A.X + $A.W
    $y1 = $A.Y + ($A.H / 2)
    $x2 = $B.X
    $y2 = $B.Y + ($B.H / 2)
    $Gfx.DrawLine($pen, $x1, $y1, $x2, $y2)
    if ($Active) {
        $dotX = $x1 + (($x2 - $x1) * $Progress)
        $dotY = $y1 + (($y2 - $y1) * $Progress)
        $Gfx.FillEllipse((Brush '#16a34a'), $dotX-10, $dotY-10, 20, 20)
    }
}

$nodes = @(
    [PSCustomObject]@{ Title='Northwind'; Sub='ERP-like source'; X=60; Y=180; W=160; H=86 },
    [PSCustomObject]@{ Title='CsvRaw'; Sub='CRM export'; X=60; Y=330; W=160; H=86 },
    [PSCustomObject]@{ Title='Snapshots'; Sub='point-in-time copies'; X=290; Y=255; W=170; H=86 },
    [PSCustomObject]@{ Title='Canonical'; Sub='normalize fields'; X=530; Y=255; W=160; H=86 },
    [PSCustomObject]@{ Title='Match Keys'; Sub='email / phone / city'; X=760; Y=255; W=165; H=86 },
    [PSCustomObject]@{ Title='Survivorship'; Sub='winner + reason'; X=995; Y=255; W=190; H=86 },
    [PSCustomObject]@{ Title='Target Model'; Sub='attribute rules'; X=205; Y=510; W=185; H=86 },
    [PSCustomObject]@{ Title='Target Load'; Sub='SAP-shaped masters'; X=465; Y=510; W=185; H=86 },
    [PSCustomObject]@{ Title='Reconcile'; Sub='100% accounted'; X=725; Y=510; W=185; H=86 },
    [PSCustomObject]@{ Title='Tests + Post'; Sub='6/6 pass + evidence'; X=985; Y=510; W=185; H=86 }
)

$edges = @(
    @(0,2), @(1,2), @(2,3), @(3,4), @(4,5), @(5,6), @(6,7), @(7,8), @(8,9)
)

$frames = 96
for ($i=0; $i -lt $frames; $i++) {
    $bmp = New-Object System.Drawing.Bitmap 1280, 720
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $g.Clear([System.Drawing.Color]::FromArgb(248,250,252))
    $g.FillRectangle((Brush '#2563eb'), 0, 0, 1280, 12)
    $g.DrawString('MigrationLab Process Flow', (FontObj 34 Bold), (Brush '#0f172a'), 54, 42)
    $g.DrawString('snapshot -> normalize -> match -> survive -> target -> reconcile -> test', (FontObj 17 Regular), (Brush '#475569'), 58, 88)

    $phase = [Math]::Floor(($i / $frames) * $nodes.Count)
    if ($phase -ge $nodes.Count) { $phase = $nodes.Count - 1 }
    $edgePhase = [Math]::Floor(($i / $frames) * $edges.Count)
    if ($edgePhase -ge $edges.Count) { $edgePhase = $edges.Count - 1 }
    $progress = (($i % [Math]::Floor($frames / $edges.Count)) / [Math]::Floor($frames / $edges.Count))

    foreach ($edge in $edges) {
        Draw-Arrow $g $nodes[$edge[0]] $nodes[$edge[1]] $false 0
    }
    $activeEdge = $edges[$edgePhase]
    Draw-Arrow $g $nodes[$activeEdge[0]] $nodes[$activeEdge[1]] $true $progress

    for ($n=0; $n -lt $nodes.Count; $n++) {
        Draw-Node $g $nodes[$n] ($n -eq $phase)
    }

    Draw-RoundedRect $g 54 630 1168 54 14 (Brush '#0f172a') (PenObj '#0f172a' 1)
    Draw-CenteredText $g 'Run result: 414 source records | 191 loaded | 223 merged | 0 rejected | 6/6 tests passed' (FontObj 19 Bold) (Brush '#ffffff') 54 630 1168 54

    $framePath = Join-Path $frameDir ('frame_{0:D4}.png' -f $i)
    $bmp.Save($framePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $bmp.Dispose()
}

Write-Host "Created $frames frames in $frameDir"
