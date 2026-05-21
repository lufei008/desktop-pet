param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'model-config.example.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

function Read-ProviderNames {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return @('local-template')
    }
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if (-not ($config.PSObject.Properties.Name -contains 'providers')) {
        return @('local-template')
    }
    return @($config.providers.PSObject.Properties.Name)
}

function Add-Label {
    param($Grid, [string]$Text, [int]$Row)

    $label = [System.Windows.Controls.TextBlock]::new()
    $label.Text = $Text
    $label.Margin = [System.Windows.Thickness]::new(0, 8, 14, 4)
    $label.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
    [System.Windows.Controls.Grid]::SetRow($label, $Row)
    [System.Windows.Controls.Grid]::SetColumn($label, 0)
    [void]$Grid.Children.Add($label)
}

function Add-TextBox {
    param($Grid, [int]$Row, [int]$Height = 28, [switch]$Multiline)

    $box = [System.Windows.Controls.TextBox]::new()
    $box.Height = $Height
    $box.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
    if ($Multiline) {
        $box.AcceptsReturn = $true
        $box.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $box.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    }
    [System.Windows.Controls.Grid]::SetRow($box, $Row)
    [System.Windows.Controls.Grid]::SetColumn($box, 1)
    [void]$Grid.Children.Add($box)
    return $box
}

function Invoke-Creator {
    param([string[]]$Arguments)

    $scriptPath = Join-Path $PSScriptRoot 'PetCreator.ps1'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }
    return ($output -join [Environment]::NewLine)
}

$window = [System.Windows.Window]::new()
$window.Title = 'Pet Studio / 宠物制作'
$window.Width = 760
$window.Height = 560
$window.MinWidth = 660
$window.MinHeight = 500
$window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen

$root = [System.Windows.Controls.Grid]::new()
$root.Margin = [System.Windows.Thickness]::new(18)
$window.Content = $root

$root.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::new(128) })
$root.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]@{ Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star) })
foreach ($height in @(38, 38, 96, 38, 38, 38, 42, 1)) {
    $row = [System.Windows.Controls.RowDefinition]::new()
    if ($height -eq 1) {
        $row.Height = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    }
    else {
        $row.Height = [System.Windows.GridLength]::new($height)
    }
    $root.RowDefinitions.Add($row)
}

Add-Label $root '宠物 ID' 0
$petIdBox = Add-TextBox $root 0
$petIdBox.Text = 'my-pet'

Add-Label $root '显示名称' 1
$displayNameBox = Add-TextBox $root 1
$displayNameBox.Text = 'My Pet'

Add-Label $root '描述' 2
$descriptionBox = Add-TextBox $root 2 -Height 86 -Multiline
$descriptionBox.Text = '一只可爱的自定义桌宠，贴纸风格。'

Add-Label $root '参考图片' 3
$referencePanel = [System.Windows.Controls.DockPanel]::new()
$referencePanel.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
$referenceBox = [System.Windows.Controls.TextBox]::new()
$referenceBox.Height = 28
$browseButton = [System.Windows.Controls.Button]::new()
$browseButton.Content = '选择'
$browseButton.Width = 78
$browseButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
[System.Windows.Controls.DockPanel]::SetDock($browseButton, [System.Windows.Controls.Dock]::Right)
[void]$referencePanel.Children.Add($browseButton)
[void]$referencePanel.Children.Add($referenceBox)
[System.Windows.Controls.Grid]::SetRow($referencePanel, 3)
[System.Windows.Controls.Grid]::SetColumn($referencePanel, 1)
[void]$root.Children.Add($referencePanel)

$browseButton.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter = 'Images|*.png;*.jpg;*.jpeg;*.webp;*.bmp|All files|*.*'
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $referenceBox.Text = $dialog.FileName
    }
})

Add-Label $root '风格' 4
$styleBox = [System.Windows.Controls.ComboBox]::new()
$styleBox.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
foreach ($style in @('sticker', 'pixel', 'plush', 'clay', 'flat-vector', '3d-toy')) {
    [void]$styleBox.Items.Add($style)
}
$styleBox.SelectedIndex = 0
[System.Windows.Controls.Grid]::SetRow($styleBox, 4)
[System.Windows.Controls.Grid]::SetColumn($styleBox, 1)
[void]$root.Children.Add($styleBox)

Add-Label $root '模型' 5
$providerBox = [System.Windows.Controls.ComboBox]::new()
$providerBox.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
foreach ($provider in Read-ProviderNames $ConfigPath) {
    [void]$providerBox.Items.Add($provider)
}
if ($providerBox.Items.Count -gt 0) {
    $providerBox.SelectedIndex = 0
}
[System.Windows.Controls.Grid]::SetRow($providerBox, 5)
[System.Windows.Controls.Grid]::SetColumn($providerBox, 1)
[void]$root.Children.Add($providerBox)

$buttonPanel = [System.Windows.Controls.StackPanel]::new()
$buttonPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
$buttonPanel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
$buttonPanel.Margin = [System.Windows.Thickness]::new(0, 8, 0, 4)

$overwriteBox = [System.Windows.Controls.CheckBox]::new()
$overwriteBox.Content = '覆盖同名'
$overwriteBox.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
$overwriteBox.Margin = [System.Windows.Thickness]::new(0, 0, 14, 0)

$createButton = [System.Windows.Controls.Button]::new()
$createButton.Content = '创建请求'
$createButton.Width = 96
$createButton.Height = 30

$generateButton = [System.Windows.Controls.Button]::new()
$generateButton.Content = '生成并安装'
$generateButton.Width = 108
$generateButton.Height = 30
$generateButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

$openRunsButton = [System.Windows.Controls.Button]::new()
$openRunsButton.Content = '打开 runs'
$openRunsButton.Width = 96
$openRunsButton.Height = 30
$openRunsButton.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)

[void]$buttonPanel.Children.Add($overwriteBox)
[void]$buttonPanel.Children.Add($createButton)
[void]$buttonPanel.Children.Add($generateButton)
[void]$buttonPanel.Children.Add($openRunsButton)
[System.Windows.Controls.Grid]::SetRow($buttonPanel, 6)
[System.Windows.Controls.Grid]::SetColumn($buttonPanel, 1)
[void]$root.Children.Add($buttonPanel)

$statusBox = [System.Windows.Controls.TextBox]::new()
$statusBox.IsReadOnly = $true
$statusBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
$statusBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
$statusBox.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
[System.Windows.Controls.Grid]::SetRow($statusBox, 7)
[System.Windows.Controls.Grid]::SetColumnSpan($statusBox, 2)
[void]$root.Children.Add($statusBox)

function New-RequestArguments {
    $args = @(
        '-Command', 'new-request',
        '-PetId', $petIdBox.Text,
        '-DisplayName', $displayNameBox.Text,
        '-Description', $descriptionBox.Text,
        '-Style', [string]$styleBox.SelectedItem,
        '-Provider', [string]$providerBox.SelectedItem,
        '-ConfigPath', $ConfigPath
    )
    if (-not [string]::IsNullOrWhiteSpace($referenceBox.Text)) {
        $args += @('-ReferenceImage', $referenceBox.Text)
    }
    return $args
}

$createButton.Add_Click({
    try {
        $statusBox.Text = Invoke-Creator (New-RequestArguments)
    }
    catch {
        $statusBox.Text = $_.Exception.Message
    }
})

$generateButton.Add_Click({
    try {
        $requestText = Invoke-Creator (New-RequestArguments)
        $request = $requestText | ConvertFrom-Json
        $args = @(
            '-Command', 'generate',
            '-RunDir', [string]$request.runDir,
            '-ConfigPath', $ConfigPath,
            '-Install'
        )
        if ($overwriteBox.IsChecked) {
            $args += '-Force'
        }
        $generateText = Invoke-Creator $args
        $statusBox.Text = $requestText + [Environment]::NewLine + [Environment]::NewLine + $generateText
    }
    catch {
        $statusBox.Text = $_.Exception.Message
    }
})

$openRunsButton.Add_Click({
    $runs = Join-Path $PSScriptRoot 'runs'
    New-Item -ItemType Directory -Force -Path $runs | Out-Null
    Start-Process explorer.exe -ArgumentList $runs
})

[void]$window.ShowDialog()
