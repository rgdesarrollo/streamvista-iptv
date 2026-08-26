Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $PSScriptRoot '..\icon.png'
$targetPath = Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico'

$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
  $bitmap = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  try {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
      $graphics.Clear([System.Drawing.Color]::Transparent)
      $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
      $graphics.DrawImage($source, 0, 0, 256, 256)
    } finally {
      $graphics.Dispose()
    }

    $pngStream = New-Object System.IO.MemoryStream
    try {
      $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
      $png = $pngStream.ToArray()
    } finally {
      $pngStream.Dispose()
    }

    $output = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter $output
    try {
      $writer.Write([UInt16]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]1)
      $writer.Write([Byte]0)
      $writer.Write([Byte]0)
      $writer.Write([Byte]0)
      $writer.Write([Byte]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]32)
      $writer.Write([UInt32]$png.Length)
      $writer.Write([UInt32]22)
      $writer.Write($png)
      [System.IO.File]::WriteAllBytes($targetPath, $output.ToArray())
    } finally {
      $writer.Dispose()
      $output.Dispose()
    }
  } finally {
    $bitmap.Dispose()
  }
} finally {
  $source.Dispose()
}
