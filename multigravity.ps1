<#
.SYNOPSIS
Run multiple Antigravity IDE profiles at the same time.
#>

param (
  [Parameter(Position = 0, Mandatory = $false)]
  [string]$cmd,
    
  [Parameter(Position = 1, Mandatory = $false)]
  [string]$arg1,

  [Parameter(Position = 2, Mandatory = $false)]
  [string]$arg2,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ForwardArgs
)

$BASE = if ($env:MULTIGRAVITY_HOME)
{ $env:MULTIGRAVITY_HOME 
} else
{ "$env:USERPROFILE\AntigravityProfiles" 
}

function Find-Antigravity
{
  $paths = @(
    "$env:LOCALAPPDATA\Programs\Antigravity\Antigravity.exe",
    "$env:PROGRAMFILES\Antigravity\Antigravity.exe",
    "${env:ProgramFiles(x86)}\Antigravity\Antigravity.exe"
  )
  foreach ($p in $paths)
  {
    if (Test-Path $p)
    { return $p 
    }
  }
    
  # Try to find in PATH
  $exeCommand = Get-Command antigravity.exe -ErrorAction SilentlyContinue
  if ($exeCommand)
  { return $exeCommand.Source 
  }
    
  return $null
}

$APP = if ($env:MULTIGRAVITY_APP)
{ $env:MULTIGRAVITY_APP 
} else
{ Find-Antigravity 
}

function Find-Agy
{
  $paths = @(
    "$env:LOCALAPPDATA\Programs\Antigravity CLI\agy.exe",
    "$env:PROGRAMFILES\Antigravity CLI\agy.exe",
    "${env:ProgramFiles(x86)}\Antigravity CLI\agy.exe"
  )
  foreach ($p in $paths)
  {
    if (Test-Path $p)
    { return $p 
    }
  }
    
  # Try to find in PATH
  $exeCommand = Get-Command agy.exe -ErrorAction SilentlyContinue
  if (!$exeCommand)
  {
    $exeCommand = Get-Command agy -ErrorAction SilentlyContinue
  }
  if ($exeCommand)
  { return $exeCommand.Source 
  }
    
  return $null
}

$CLI = if ($env:MULTIGRAVITY_CLI)
{ $env:MULTIGRAVITY_CLI 
} elseif ($env:MULTIGRAVITY_AGY)
{ $env:MULTIGRAVITY_AGY 
} else
{ Find-Agy 
}


function Get-TemplatesDir
{
  return "$BASE\.templates"
}

function Get-SystemDataDir
{
  return "$env:APPDATA\Antigravity"
}

function Get-SystemExtensionsDir
{
  return "$env:USERPROFILE\.antigravity\extensions"
}

function Test-SharedProfile
{
  param($name)
  return Test-Path "$BASE\$name\.shared"
}

function Test-LinkedProfile
{
  param($name)
  return Test-Path "$BASE\$name\.linked"
}

function Write-Usage
{
  Write-Output "Usage: multigravity <command> [args]"
  Write-Output ""
  Write-Output "Commands:"
  Write-Output "  new <name> [options]        Create a new profile + Start Menu shortcut"
  Write-Output "      --shared                Share extensions & settings; isolate only accounts"
  Write-Output "      --linked                Share extensions, settings, history & cache; isolate only accounts"
  Write-Output "      --from <template>        Seed from a saved template"
  Write-Output "  list                        List existing profiles"
  Write-Output "  status                      Show running state, type, and last-used per profile"
  Write-Output "  rename <old> <new>          Rename a profile (updates shortcut if present)"
  Write-Output "  delete <name>               Delete a profile and its data"
  Write-Output "  clone <src> <dest>          Copy an existing profile"
  Write-Output "  template save <profile> <name>   Save a profile as a reusable template"
  Write-Output "  template list               List saved templates"
  Write-Output "  template delete <name>      Remove a template"
  Write-Output "  export <name> [path]        Archive a profile to a .zip file"
  Write-Output "  import <archive> [name]     Restore a profile from a .zip archive"
  Write-Output "  update                      Update multigravity to the latest version"
  Write-Output "  doctor                      Run a system diagnosis"
  Write-Output "  stats                       Show storage usage per profile"
  Write-Output "  completion                  Show setup instructions for shell completion"
  Write-Output "  agy <name> [args...]        Launch Antigravity CLI (agy) with the given profile"
  Write-Output "  <name> [args...]            Launch Antigravity IDE with the given profile"
  Write-Output "  help                        Show this help"
  Write-Output ""
  Write-Output "Profile names: alphanumeric and hyphens only (e.g. work, personal, test-1)"
}

function Validate-Name
{
  param($name)
  if ([string]::IsNullOrWhiteSpace($name))
  {
    Write-Error "Error: profile name required"
    exit 1
  }
  if ($name -notmatch "^[a-zA-Z0-9][a-zA-Z0-9-]*$")
  {
    Write-Error "Error: profile name must start with alphanumeric and contain only letters, numbers, or hyphens"
    exit 1
  }
}

function Invoke-CreateProfile
{
  param($PROFILE)
  $PROFILE_DIR = "$BASE\$PROFILE"
    
  New-Item -ItemType Directory -Force -Path "$PROFILE_DIR\.antigravity\extensions" | Out-Null
  New-Item -ItemType Directory -Force -Path "$PROFILE_DIR\AppData\Roaming" | Out-Null
  New-Item -ItemType Directory -Force -Path "$PROFILE_DIR\AppData\Local" | Out-Null
}

function Invoke-CreateSharedProfile
{
  param($name)
  $profileDir = "$BASE\$name"
  $sysData     = Get-SystemDataDir
  $sysExt      = Get-SystemExtensionsDir

  New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
  New-Item -ItemType File      -Force -Path "$profileDir\.shared" | Out-Null

  # Isolated AppData so accounts don't bleed across profiles
  $userDataDir = "$profileDir\AppData\Roaming\Antigravity\User"
  New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
  New-Item -ItemType Directory -Force -Path "$profileDir\AppData\Local" | Out-Null

  # Symlink settings files from the system install so they stay in sync
  if (Test-Path "$sysData\User")
  {
    foreach ($f in @("settings.json", "keybindings.json", "snippets"))
    {
      $src  = "$sysData\User\$f"
      $dest = "$userDataDir\$f"
      if ((Test-Path $src) -and !(Test-Path $dest))
      {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src -ErrorAction SilentlyContinue | Out-Null
      }
    }
  }

  # Point extensions at the system folder instead of an empty private copy
  $extDir = "$profileDir\.antigravity\extensions"
  if (Test-Path $sysExt)
  {
    if (Test-Path $extDir)
    { Remove-Item $extDir -Force -ErrorAction SilentlyContinue 
    }
    New-Item -ItemType Directory -Force -Path "$profileDir\.antigravity" | Out-Null
    New-Item -ItemType SymbolicLink -Path $extDir -Target $sysExt -ErrorAction SilentlyContinue | Out-Null
  } else
  {
    New-Item -ItemType Directory -Force -Path $extDir | Out-Null
  }

  # CLI settings symlink
  $sysAgySettings = "$env:USERPROFILE\.gemini\antigravity-cli\settings.json"
  $profileAgySettings = "$profileDir\.gemini\antigravity-cli\settings.json"
  if ((Test-Path $sysAgySettings) -and !(Test-Path $profileAgySettings))
  {
    New-Item -ItemType Directory -Force -Path (Split-Path $profileAgySettings) | Out-Null
    New-Item -ItemType SymbolicLink -Path $profileAgySettings -Target $sysAgySettings -ErrorAction SilentlyContinue | Out-Null
  }
}

function Invoke-CreateLinkedProfile
{
  param($name)
  $profileDir = "$BASE\$name"
  $sysData     = Get-SystemDataDir
  $sysExt      = Get-SystemExtensionsDir

  New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
  New-Item -ItemType File      -Force -Path "$profileDir\.linked" | Out-Null

  # Isolated AppData so accounts don't bleed across profiles
  $userDataDir = "$profileDir\AppData\Roaming\Antigravity\User"
  New-Item -ItemType Directory -Force -Path $userDataDir | Out-Null
  New-Item -ItemType Directory -Force -Path "$profileDir\AppData\Local" | Out-Null

  # Symlink settings files from the system install so they stay in sync
  if (Test-Path "$sysData\User")
  {
    foreach ($f in @("settings.json", "keybindings.json", "snippets"))
    {
      $src  = "$sysData\User\$f"
      $dest = "$userDataDir\$f"
      if ((Test-Path $src) -and !(Test-Path $dest))
      {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src -ErrorAction SilentlyContinue | Out-Null
      }
    }
    # Symlink workspaceStorage, Backups, History
    foreach ($d in @("workspaceStorage", "Backups", "History"))
    {
      $src  = "$sysData\$d"
      $dest = "$profileDir\AppData\Roaming\Antigravity\$d"
      if ((Test-Path $src) -and !(Test-Path $dest))
      {
        New-Item -ItemType SymbolicLink -Path $dest -Target $src -ErrorAction SilentlyContinue | Out-Null
      }
    }
    # Symlink globalStorage subdirectories (isolate json and vscdb files)
    if (Test-Path "$sysData\User\globalStorage")
    {
      $destGlobal = "$userDataDir\globalStorage"
      New-Item -ItemType Directory -Force -Path $destGlobal | Out-Null
      $entries = Get-ChildItem -Directory -Path "$sysData\User\globalStorage"
      foreach ($entry in $entries)
      {
        $destDir = "$destGlobal\$($entry.Name)"
        if (!(Test-Path $destDir))
        {
          New-Item -ItemType SymbolicLink -Path $destDir -Target $entry.FullName -ErrorAction SilentlyContinue | Out-Null
        }
      }
    }
  }

  # Point extensions at the system folder instead of an empty private copy
  $extDir = "$profileDir\.antigravity\extensions"
  if (Test-Path $sysExt)
  {
    if (Test-Path $extDir)
    { Remove-Item $extDir -Force -ErrorAction SilentlyContinue 
    }
    New-Item -ItemType Directory -Force -Path "$profileDir\.antigravity" | Out-Null
    New-Item -ItemType SymbolicLink -Path $extDir -Target $sysExt -ErrorAction SilentlyContinue | Out-Null
  } else
  {
    New-Item -ItemType Directory -Force -Path $extDir | Out-Null
  }

  # CLI (agy) configurations & data sharing
  $sysGemini = "$env:USERPROFILE\.gemini"
  $profileGemini = "$profileDir\.gemini"
  if (Test-Path $sysGemini)
  {
    New-Item -ItemType Directory -Force -Path "$profileGemini\antigravity-cli" | Out-Null
        
    $sysAgySettings = "$sysGemini\settings.json"
    $profileAgySettings = "$profileGemini\settings.json"
    if ((Test-Path $sysAgySettings) -and !(Test-Path $profileAgySettings))
    {
      New-Item -ItemType SymbolicLink -Path $profileAgySettings -Target $sysAgySettings -ErrorAction SilentlyContinue | Out-Null
    }
        
    $sysAgySettings2 = "$sysGemini\antigravity-cli\settings.json"
    $profileAgySettings2 = "$profileGemini\antigravity-cli\settings.json"
    if ((Test-Path $sysAgySettings2) -and !(Test-Path $profileAgySettings2))
    {
      New-Item -ItemType SymbolicLink -Path $profileAgySettings2 -Target $sysAgySettings2 -ErrorAction SilentlyContinue | Out-Null
    }

    foreach ($item in @("conversations", "brain", "cache", "knowledge", "scratch", "implicit", "log", "history.jsonl"))
    {
      $srcPath = "$sysGemini\antigravity-cli\$item"
      $destPath = "$profileGemini\antigravity-cli\$item"
      if ((Test-Path $srcPath) -and !(Test-Path $destPath))
      {
        New-Item -ItemType SymbolicLink -Path $destPath -Target $srcPath -ErrorAction SilentlyContinue | Out-Null
      }
    }
  }
}


function Invoke-LaunchProfile
{
  param($PROFILE, $ArgsToForward)
  $PROFILE_DIR = "$BASE\$PROFILE"

  if (!(Test-Path $PROFILE_DIR))
  {
    Write-Error "Error: profile '$PROFILE' does not exist. Run: multigravity new $PROFILE"
    exit 1
  }

  if (Test-LinkedProfile $PROFILE)
  {
    Invoke-CreateLinkedProfile $PROFILE
  } elseif (Test-SharedProfile $PROFILE)
  {
    Invoke-CreateSharedProfile $PROFILE
  }

  if ([string]::IsNullOrEmpty($APP) -or !(Test-Path $APP))
  {
    Write-Error "Error: Antigravity.exe not found"
    exit 1
  }

  Write-Output "Launching Antigravity profile '$PROFILE'"
    
  # Launch Antigravity with isolated USERPROFILE
  $env:USERPROFILE = $PROFILE_DIR
  $env:APPDATA = "$PROFILE_DIR\AppData\Roaming"
  $env:LOCALAPPDATA = "$PROFILE_DIR\AppData\Local"
    
  if ($ArgsToForward)
  {
    Start-Process -FilePath $APP -ArgumentList $ArgsToForward
  } else
  {
    Start-Process -FilePath $APP
  }
}

function Invoke-LaunchAgyProfile
{
  param($PROFILE, $ArgsToForward)
  $PROFILE_DIR = "$BASE\$PROFILE"

  if (!(Test-Path $PROFILE_DIR))
  {
    Write-Error "Error: profile '$PROFILE' does not exist. Run: multigravity new $PROFILE"
    exit 1
  }

  if (Test-LinkedProfile $PROFILE)
  {
    Invoke-CreateLinkedProfile $PROFILE
  } elseif (Test-SharedProfile $PROFILE)
  {
    Invoke-CreateSharedProfile $PROFILE
  }

  if ([string]::IsNullOrEmpty($CLI) -or !(Test-Path $CLI))
  {
    Write-Error "Error: Antigravity CLI (agy) not found"
    exit 1
  }

  Write-Output "Launching Antigravity CLI 'agy' with profile '$PROFILE'"

  $env:USERPROFILE = $PROFILE_DIR
  $env:APPDATA = "$PROFILE_DIR\AppData\Roaming"
  $env:LOCALAPPDATA = "$PROFILE_DIR\AppData\Local"
  $env:MULTIGRAVITY_PROFILE = $PROFILE

  if ($ArgsToForward)
  {
    & $CLI $ArgsToForward
  } else
  {
    & $CLI
  }
}


function Invoke-ListProfiles
{
  param($raw)
  if ($raw -ne "--raw")
  {
    Write-Output "Existing profiles:"
  }
  if (Test-Path $BASE)
  {
    $profiles = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.PSIsContainer -and $_.Name -ne ".templates" } | Sort-Object Name
    if ($profiles.Count -gt 0)
    {
      foreach ($p in $profiles)
      {
        if ($raw -eq "--raw")
        {
          Write-Output "$($p.Name)"
        } else
        {
          $suffix = ""
          if (Test-Path "$($p.FullName)\.shared")
          {
            $suffix = " (shared)"
          } elseif (Test-Path "$($p.FullName)\.linked")
          {
            $suffix = " (linked)"
          }
          Write-Output "$($p.Name)$suffix"
        }
      }
    } elseif ($profiles -is [System.IO.DirectoryInfo])
    {
      if ($raw -eq "--raw")
      {
        Write-Output "$($profiles.Name)"
      } else
      {
        $suffix = ""
        if (Test-Path "$($profiles.FullName)\.shared")
        {
          $suffix = " (shared)"
        } elseif (Test-Path "$($profiles.FullName)\.linked")
        {
          $suffix = " (linked)"
        }
        Write-Output "$($profiles.Name)$suffix"
      }
    } else
    {
      if ($raw -ne "--raw")
      {
        Write-Output "(none)"
      }
    }
  } else
  {
    if ($raw -ne "--raw")
    {
      Write-Output "(none)"
    }
  }
}

function Invoke-CreateShortcut
{
  param($PROFILE)
  $APP_NAME = "Multigravity $PROFILE"
  $SHORTCUT_PATH = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$APP_NAME.lnk"
    
  $SCRIPT_PATH = $MyInvocation.MyCommand.Path
  # If script path is empty (e.g. running from prompt), try to find it
  if ([string]::IsNullOrEmpty($SCRIPT_PATH))
  {
    $cmdObj = Get-Command multigravity -ErrorAction SilentlyContinue
    if ($cmdObj)
    { $SCRIPT_PATH = $cmdObj.Source 
    }
  }
    
  $WshShell = New-Object -comObject WScript.Shell
  $Shortcut = $WshShell.CreateShortcut($SHORTCUT_PATH)
  $Shortcut.TargetPath = "powershell.exe"
  $Shortcut.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -Command `"& '$SCRIPT_PATH' $PROFILE`""
  if ($APP)
  {
    $Shortcut.IconLocation = "$APP, 0"
  }
  $Shortcut.Save()

  Write-Output "Shortcut created: $SHORTCUT_PATH"
}

function Invoke-NewProfile
{
  param($name, [string[]]$extraArgs)

  $shared      = $false
  $linked      = $false
  $fromTpl     = ""
  $i = 0
  while ($i -lt $extraArgs.Count)
  {
    switch ($extraArgs[$i])
    {
      "--shared"
      { $shared = $true 
      }
      "--linked"
      { $linked = $true 
      }
      "--from"
      { $i++; if ($i -lt $extraArgs.Count)
        { $fromTpl = $extraArgs[$i] 
        } 
      }
    }
    $i++
  }

  if ($shared -and $linked)
  {
    Write-Error "Error: cannot specify both --shared and --linked"
    exit 1
  }

  if ([string]::IsNullOrWhiteSpace($name))
  {
    Write-Error "Error: profile name required"
    exit 1
  }

  Validate-Name $name

  $profileDir = "$BASE\$name"
  if (Test-Path $profileDir)
  {
    Write-Error "Error: profile '$name' already exists"
    exit 1
  }

  New-Item -ItemType Directory -Force -Path $BASE | Out-Null

  if ($fromTpl)
  {
    $tplPath = "$(Get-TemplatesDir)\$fromTpl"
    if (!(Test-Path $tplPath))
    {
      Write-Error "Error: template '$fromTpl' not found. Run: multigravity template list"
      exit 1
    }
    Write-Output "Creating profile '$name' from template '$fromTpl'..."
    Copy-Item -Path $tplPath -Destination $profileDir -Recurse
  } elseif ($shared)
  {
    Invoke-CreateSharedProfile $name
  } elseif ($linked)
  {
    Invoke-CreateLinkedProfile $name
  } else
  {
    Invoke-CreateProfile $name
  }

  Write-Output "Created profile '$name'"
  Invoke-CreateShortcut $name
}

function Invoke-DeleteProfile
{
  param($PROFILE)
  Validate-Name $PROFILE

  $PROFILE_DIR = "$BASE\$PROFILE"
  if (!(Test-Path $PROFILE_DIR))
  {
    Write-Error "Error: profile '$PROFILE' does not exist"
    exit 1
  }

  $confirm = Read-Host "Delete profile '$PROFILE' and all its data? [y/N]"
  if ($confirm -match "^[Yy]$")
  {
    try
    {
      Remove-Item -Recurse -Force $PROFILE_DIR -ErrorAction Stop
            
      $SHORTCUT_PATH = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Multigravity $PROFILE.lnk"
      if (Test-Path $SHORTCUT_PATH)
      {
        Remove-Item -Force $SHORTCUT_PATH
        Write-Output "Removed shortcut: $SHORTCUT_PATH"
      }
      Write-Output "Deleted profile '$PROFILE'"
    } catch
    {
      Write-Error "Error: could not delete profile directory. Ensure Antigravity is closed and no files are in use."
      Write-Output "Details: $_"
    }
  } else
  {
    Write-Output "Aborted."
  }
}

function Invoke-RenameProfile
{
  param($OLD, $NEW)
  Validate-Name $OLD
  Validate-Name $NEW

  $OLD_DIR = "$BASE\$OLD"
  $NEW_DIR = "$BASE\$NEW"

  if (!(Test-Path $OLD_DIR))
  {
    Write-Error "Error: profile '$OLD' does not exist"
    exit 1
  }
  if (Test-Path $NEW_DIR)
  {
    Write-Error "Error: profile '$NEW' already exists"
    exit 1
  }

  Rename-Item -Path $OLD_DIR -NewName $NEW

  $OLD_SHORTCUT = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Multigravity $OLD.lnk"
  if (Test-Path $OLD_SHORTCUT)
  {
    Remove-Item -Force $OLD_SHORTCUT
    Invoke-CreateShortcut $NEW
  }

  Write-Output "Renamed profile '$OLD' to '$NEW'"
}

function Invoke-CloneProfile
{
  param($SRC, $DEST)
  Validate-Name $SRC
  Validate-Name $DEST

  $SRC_DIR = "$BASE\$SRC"
  $DEST_DIR = "$BASE\$DEST"

  if (!(Test-Path $SRC_DIR))
  {
    Write-Error "Error: source profile '$SRC' does not exist"
    exit 1
  }
  if (Test-Path $DEST_DIR)
  {
    Write-Error "Error: destination profile '$DEST' already exists"
    exit 1
  }

  Write-Output "Cloning profile '$SRC' to '$DEST'..."
  Copy-Item -Path $SRC_DIR -Destination $DEST_DIR -Recurse
  Invoke-CreateShortcut $DEST

  Write-Output "Successfully cloned '$SRC' to '$DEST'"
}

function Get-FolderSize
{
  param($Path)
  $size = (Get-ChildItem $Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if ($size -ge 1GB)
  { "{0:N2} GB" -f ($size / 1GB) 
  } elseif ($size -ge 1MB)
  { "{0:N2} MB" -f ($size / 1MB) 
  } elseif ($size -ge 1KB)
  { "{0:N2} KB" -f ($size / 1KB) 
  } else
  { "$size B" 
  }
}

function Invoke-ProfileStats
{
  if (!(Test-Path $BASE))
  {
    Write-Output "No profiles found."
    return
  }

  Write-Output "Profile Storage Usage:"
  Write-Output ("{0,-20} {1,-10} {2,-10}" -f "PROFILE", "SIZE", "EXTENSIONS")
  Write-Output ("{0,-20} {1,-10} {2,-10}" -f "-------", "----", "----------")

  $profiles = Get-ChildItem -Directory -Path $BASE | Where-Object { $_.Name -ne ".templates" }
  foreach ($p in $profiles)
  {
    $size = Get-FolderSize $p.FullName
    $extPath = Join-Path $p.FullName ".antigravity\extensions"
    $extCount = if (Test-Path $extPath)
    { (Get-ChildItem $extPath).Count 
    } else
    { 0 
    }
    Write-Output ("{0,-20} {1,-10} {2,-10}" -f $p.Name, $size, $extCount)
  }

  Write-Output ""
  $total = Get-FolderSize $BASE
  Write-Output "Total usage: $total"
}

function Invoke-DoctorCli
{
  $errors = 0
  $warnings = 0

  Write-Output "Checking multigravity environment..."

  # 1. Antigravity IDE Installation
  if ($APP -and (Test-Path $APP))
  {
    Write-Output "  [OK] Antigravity IDE: Found at $APP"
  } else
  {
    Write-Output "  [WARN] Antigravity IDE: Not found. (Optional if using only CLI)"
    $warnings++
  }

  # 1b. Antigravity CLI (agy) Installation
  if ($CLI -and (Test-Path $CLI))
  {
    Write-Output "  [OK] Antigravity CLI (agy): Found at $CLI"
  } else
  {
    Write-Output "  [WARN] Antigravity CLI (agy): Not found. (Optional if using only IDE)"
    $warnings++
  }

  # 2. Path Check
  $cmdObj = Get-Command multigravity -ErrorAction SilentlyContinue
  if ($cmdObj)
  {
    Write-Output "  [OK] Global Binary: $($cmdObj.Source)"
  } else
  {
    Write-Output "  [WARN] Global Binary: Not found in PATH. Run install script or update PATH."
    $warnings++
  }

  # 3. Base Directory
  if (Test-Path $BASE)
  {
    # Check writability
    try
    {
      $testFile = Join-Path $BASE ".write-test"
      New-Item -ItemType File -Path $testFile -Force -ErrorAction Stop | Out-Null
      Remove-Item $testFile -Force
      Write-Output "  [OK] Profile storage: $BASE (writable)"
    } catch
    {
      Write-Output "  [FAIL] Profile storage: $BASE (NOT writable)"
      $errors++
    }
  } else
  {
    Write-Output "  [WARN] Profile storage: $BASE (Not yet created)"
  }

  Write-Output ""
  if ($errors -eq 0)
  {
    if ($warnings -eq 0)
    {
      Write-Output "Your environment looks perfect!"
    } else
    {
      Write-Output "Found $warnings warning(s). Multigravity should still work, but some features might be degraded."
    }
  } else
  {
    Write-Output "Found $errors error(s) and $warnings warning(s). Please fix the errors above."
  }
}

function Invoke-UpdateCli
{
  $script_url = "https://raw.githubusercontent.com/sujitagarwal/multigravity-cli/main/multigravity.ps1"
  $target = $MyInvocation.MyCommand.Path
  if ([string]::IsNullOrEmpty($target))
  {
    $cmdObj = Get-Command multigravity -ErrorAction SilentlyContinue
    if ($cmdObj)
    { $target = $cmdObj.Source 
    }
  }

  if ([string]::IsNullOrEmpty($target))
  {
    Write-Error "Error: could not determine script path for update"
    exit 1
  }

  Write-Output "Updating multigravity from $script_url ..."
  try
  {
    $result = Invoke-WebRequest -Uri $script_url -UseBasicParsing -ErrorAction Stop
    [System.IO.File]::WriteAllText($target, $result.Content, [System.Text.Encoding]::UTF8)
    Write-Output "Successfully updated multigravity!"
  } catch
  {
    Write-Error "Error: failed to download update: $_"
    exit 1
  }
}

function Invoke-HelpCompletion
{
  Write-Output "To enable autocompletion in PowerShell, add the following to your `$PROFILE:"
  Write-Output ""
  Write-Output '  Invoke-Expression (& multigravity completion powershell)'
  Write-Output ""
  Write-Output "Then restart your terminal or run: . `$PROFILE"
}

function Invoke-GenerateCompletion
{
  param($shell)
  if ($shell -eq "powershell")
  {
    @"
Register-ArgumentCompleter -Native -CommandName multigravity -ScriptBlock {
    param(`$wordToComplete, `$commandAst, `$cursorPosition)
    `$opts = @('new', 'list', 'status', 'rename', 'delete', 'clone', 'template', 'export', 'import', 'update', 'doctor', 'stats', 'completion', 'agy', 'help')
    `$profiles = if (Test-Path '$BASE') { Get-ChildItem -Directory -Path '$BASE' | Select-Object -ExpandProperty Name } else { @() }
    (`$opts + `$profiles) | Where-Object { `$_ -like "`$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new(`$_, `$_, 'ParameterValue', `$_)
    }
}
"@
  } else
  {
    Write-Output "Only 'powershell' completion is supported on Windows."
  }
}

function Invoke-TemplateCmd
{
  param($sub, $a, $b)
  switch ($sub)
  {
    "save"
    {
      if ([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b))
      {
        Write-Error "Error: usage: multigravity template save <profile> <name>"; exit 1
      }
      Validate-Name $a; Validate-Name $b
      $srcDir  = "$BASE\$a"
      $tplDir  = Get-TemplatesDir
      $tplPath = "$tplDir\$b"
      if (!(Test-Path $srcDir))
      { Write-Error "Error: profile '$a' does not exist"; exit 1 
      }
      if (Test-Path $tplPath)
      { Write-Error "Error: template '$b' already exists"; exit 1 
      }
      New-Item -ItemType Directory -Force -Path $tplDir | Out-Null
      Write-Output "Saving '$a' as template '$b'..."
      Copy-Item -Path $srcDir -Destination $tplPath -Recurse
      $marker = "$tplPath\.shared"
      if (Test-Path $marker)
      { Remove-Item $marker -Force 
      }
      Write-Output "Saved template '$b'"
    }
    "list"
    {
      $tplDir = Get-TemplatesDir
      Write-Output "Templates:"
      if (!(Test-Path $tplDir))
      { Write-Output "  (none)"; return 
      }
      $items = Get-ChildItem -Directory -Path $tplDir -ErrorAction SilentlyContinue
      if ($items.Count -eq 0)
      { Write-Output "  (none)"; return 
      }
      foreach ($t in $items)
      {
        Write-Output ("  {0,-20} {1}" -f $t.Name, (Get-FolderSize $t.FullName))
      }
    }
    "delete"
    {
      if ([string]::IsNullOrWhiteSpace($a))
      { Write-Error "Error: template name required"; exit 1 
      }
      Validate-Name $a
      $tplPath = "$(Get-TemplatesDir)\$a"
      if (!(Test-Path $tplPath))
      { Write-Error "Error: template '$a' does not exist"; exit 1 
      }
      Remove-Item -Recurse -Force $tplPath
      Write-Output "Deleted template '$a'"
    }
    default
    {
      Write-Error "Error: usage: multigravity template <save|list|delete>"; exit 1
    }
  }
}

function Invoke-StatusProfiles
{
  if (!(Test-Path $BASE))
  { Write-Output "No profiles found."; return 
  }

  Write-Output ("{0,-18} {1,-10} {2,-12} {3,-20} {4}" -f "PROFILE", "RUNNING", "TYPE", "LAST USED", "SIZE")
  Write-Output ("{0,-18} {1,-10} {2,-12} {3,-20} {4}" -f "-------", "-------", "----", "---------", "----")

  $dirs = Get-ChildItem -Directory -Path $BASE -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne ".templates" }

  foreach ($d in $dirs)
  {
    $running = "no"
    $procs = Get-Process -Name "Antigravity" -ErrorAction SilentlyContinue
    if ($procs)
    {
      foreach ($proc in $procs)
      {
        try
        {
          $cl = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)" -ErrorAction SilentlyContinue).CommandLine
          if ($cl -and $cl -like "*$($d.Name)*")
          { $running = "yes"; break 
          }
        } catch
        {
        }
      }
    }

    $ptype    = if (Test-Path "$($d.FullName)\.shared")
    { "shared" 
    } elseif (Test-Path "$($d.FullName)\.linked")
    { "linked" 
    } else
    { "full" 
    }
    $lastUsed = $d.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
    $size     = Get-FolderSize $d.FullName

    if ($running -eq "yes")
    {
      Write-Output ("{0,-18} " -f $d.Name) -NoNewline
      Write-Output ("{0,-10} " -f $running) -NoNewline -ForegroundColor Green
      Write-Output ("{0,-12} {1,-20} {2}" -f $ptype, $lastUsed, $size)
    } else
    {
      Write-Output ("{0,-18} {1,-10} {2,-12} {3,-20} {4}" -f $d.Name, $running, $ptype, $lastUsed, $size)
    }
  }
}

function Invoke-ExportProfile
{
  param($name, $outPath)
  if ([string]::IsNullOrWhiteSpace($name))
  { Write-Error "Error: profile name required"; exit 1 
  }
  Validate-Name $name

  $profileDir = "$BASE\$name"
  if (!(Test-Path $profileDir))
  { Write-Error "Error: profile '$name' does not exist"; exit 1 
  }

  if ([string]::IsNullOrWhiteSpace($outPath))
  { $outPath = ".\$name.zip" 
  }

  Write-Output "Exporting '$name' to $outPath ..."
  Compress-Archive -Path $profileDir -DestinationPath $outPath -Force
  Write-Output "Done."
}

function Invoke-ImportProfile
{
  param($archivePath, $name)

  if ([string]::IsNullOrWhiteSpace($archivePath))
  {
    Write-Error "Error: usage: multigravity import <archive.zip> [name]"; exit 1
  }
  if (!(Test-Path $archivePath))
  {
    Write-Error "Error: file not found: $archivePath"; exit 1
  }

  if ([string]::IsNullOrWhiteSpace($name))
  {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($archivePath)
  }
  Validate-Name $name

  $dest = "$BASE\$name"
  if (Test-Path $dest)
  {
    Write-Error "Error: profile '$name' already exists — choose a different name or delete it first"
    exit 1
  }

  New-Item -ItemType Directory -Force -Path $BASE | Out-Null
  Write-Output "Importing as '$name'..."

  $tmp = "$BASE\_mg_import_$(Get-Random)"
  Expand-Archive -Path $archivePath -DestinationPath $tmp -Force

  $top = Get-ChildItem -Directory -Path $tmp
  if ($top.Count -eq 1)
  {
    Move-Item -Path $top[0].FullName -Destination $dest
    Remove-Item $tmp -Recurse -Force
  } else
  {
    Rename-Item -Path $tmp -NewName $name
  }

  Invoke-CreateShortcut $name
  Write-Output "Imported profile '$name'"
}

switch ($cmd)
{
  "new"
  {
    $extra = @()
    if ($arg2)
    { $extra += $arg2 
    }
    if ($ForwardArgs)
    { $extra += $ForwardArgs 
    }
    Invoke-NewProfile $arg1 $extra
  }
  "list"
  {
    Invoke-ListProfiles $arg1
  }
  "status"
  {
    Invoke-StatusProfiles
  }
  "rename"
  {
    Invoke-RenameProfile $arg1 $arg2
  }
  "delete"
  {
    Invoke-DeleteProfile $arg1
  }
  "clone"
  {
    Invoke-CloneProfile $arg1 $arg2
  }
  "template"
  {
    Invoke-TemplateCmd $arg1 $arg2 ($ForwardArgs | Select-Object -First 1)
  }
  "export"
  {
    Invoke-ExportProfile $arg1 $arg2
  }
  "import"
  {
    Invoke-ImportProfile $arg1 $arg2
  }
  "update"
  {
    Invoke-UpdateCli
  }
  "doctor"
  {
    Invoke-DoctorCli
  }
  "stats"
  {
    Invoke-ProfileStats
  }
  "agy"
  {
    if ([string]::IsNullOrWhiteSpace($arg1))
    {
      Write-Error "Error: usage: multigravity agy <profile> [args...]"
      exit 1
    }
    $AllForward = @()
    if ($arg2)
    { $AllForward += $arg2 
    }
    if ($ForwardArgs)
    { $AllForward += $ForwardArgs 
    }
    Invoke-LaunchAgyProfile $arg1 $AllForward
  }
  "completion"
  {
    if ($arg1)
    {
      Invoke-GenerateCompletion $arg1
    } else
    {
      Invoke-HelpCompletion
    }
  }
  "help"
  { Write-Usage 
  }
  "--help"
  { Write-Usage 
  }
  "-h"
  { Write-Usage 
  }
  ""
  {
    Write-Usage
    exit 1
  }
  default
  {
    $AllArgs = @()
    if ($arg1)
    { $AllArgs += $arg1 
    }
    if ($arg2)
    { $AllArgs += $arg2 
    }
    if ($ForwardArgs)
    { $AllArgs += $ForwardArgs 
    }
    Invoke-LaunchProfile $cmd $AllArgs
  }
}
