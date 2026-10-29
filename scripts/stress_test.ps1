# Script de stress test automatique pour le container TeamSpeak (TS3).
# Compatible PowerShell 5.1+
# Tests cibles : ServerQuery TCP port 10011, UDP voix port 9987.
# Auto-scaling horizontal : spawn de nouveaux containers si CPU > seuil.
# Rapport ecrit dans .\scripts\stress_report.md a la fin.
#
# Prerequis : docker compose up --build -d doit etre lance avant.
# Lancement  : .\scripts\stress_test.ps1

# ===================================================================
# CONFIGURATION
# ===================================================================

$SCRIPT_DIR    = $PSScriptRoot
$REPORT_PATH   = "$SCRIPT_DIR\stress_report.md"

$API_URL       = "http://localhost:8080/api"
$TS3_UDP_HOST  = "127.0.0.1"
$TS3_UDP_PORT  = 9987

$CPU_SCALE_UP  = 60     # % CPU -> spawn replica suivant
$CPU_STOP      = 80     # % CPU replica 3 -> stop automatique
$MONITOR_SEC   = 2      # secondes entre chaque lecture CPU

$CONTAINER_R1  = "webserver_app"
$CONTAINER_R2  = "webserver_r2"
$CONTAINER_R3  = "webserver_r3"
$CPU_R1        = "0.25"
$CPU_R2        = "0.45"
$CPU_R3        = "0.65"

# ===================================================================
# UTILITAIRES
# ===================================================================

$script:Report    = New-Object System.Collections.Generic.List[string]
$script:StartTime = Get-Date

function Log {
    param([string]$Msg, [string]$Color = "White")
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "[$ts] $Msg" -ForegroundColor $Color
    $script:Report.Add("[$ts] $Msg")
}

function LogSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    $script:Report.Add("")
    $script:Report.Add("---")
    $script:Report.Add("## $Title")
}

function LogTableHeader {
    $script:Report.Add("")
    $script:Report.Add("| Etat | Test | Resultat |")
    $script:Report.Add("|---|---|---|")
}

function LogResult {
    param([string]$Label, [string]$Value, [bool]$Ok = $true)
    $ts    = (Get-Date).ToString("HH:mm:ss")
    $icon  = if ($Ok) { "[OK]  " } else { "[FAIL]" }
    $color = if ($Ok) { "Green" } else { "Red" }
    Write-Host "[$ts] $icon $Label : $Value" -ForegroundColor $color
    $mdIcon = if ($Ok) { "OK" } else { "FAIL" }
    $script:Report.Add("| $mdIcon | $Label | $Value |")
}

function Get-ContainerCpu {
    param([string]$Name)
    try {
        $raw = docker stats $Name --no-stream --format "{{.CPUPerc}}" 2>$null
        if ($raw -match "([\d.]+)%") { return [double]$Matches[1] }
    } catch {}
    return -1
}

function Test-ContainerRunning {
    param([string]$Name)
    $state = docker inspect --format "{{.State.Running}}" $Name 2>$null
    return ($state -eq "true")
}

function Invoke-Api {
    param([string]$Ep, [int]$TimeoutSec = 8)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -Uri "$API_URL/$Ep" -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop
        $sw.Stop()
        return @{ Status = $r.StatusCode; Ms = [int]$sw.ElapsedMilliseconds }
    } catch {
        $sw.Stop()
        return @{ Status = 0; Ms = [int]$sw.ElapsedMilliseconds }
    }
}

# Parallelisme compatible PS 5.1 via Start-Job
function Invoke-ParallelApi {
    param([string]$Ep, [int]$Count)
    $jobs = @()
    for ($i = 1; $i -le $Count; $i++) {
        $jobs += Start-Job -ScriptBlock {
            param($Url, $Endpoint)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $r = Invoke-WebRequest -Uri "$Url/$Endpoint" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                $sw.Stop()
                if ($r.StatusCode -eq 200) { return @{ Ok = $true; Ms = [int]$sw.ElapsedMilliseconds } }
                else                       { return @{ Ok = $false; Ms = 0 } }
            } catch {
                $sw.Stop()
                return @{ Ok = $false; Ms = 0 }
            }
        } -ArgumentList $API_URL, $Ep
    }

    $results = $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job -Force

    $lats  = @($results | Where-Object { $_.Ok  } | ForEach-Object { $_.Ms })
    $nerrs = @($results | Where-Object { -not $_.Ok }).Count

    $avg = if ($lats.Count -gt 0) { [int]($lats | Measure-Object -Average).Average } else { 9999 }
    $max = if ($lats.Count -gt 0) { ($lats | Measure-Object -Maximum).Maximum }       else { 9999 }
    return @{ Avg = $avg; Max = $max; Errors = $nerrs; Success = $lats.Count }
}

function Send-UdpPackets {
    param([int]$Count, [string]$Phase)
    Log "UDP TS3 port $TS3_UDP_PORT : envoi $Count paquets 512B (phase $Phase)" "DarkYellow"
    $errs = 0
    try {
        $udp     = New-Object System.Net.Sockets.UdpClient
        $payload = New-Object byte[] 512
        $udp.Connect($TS3_UDP_HOST, $TS3_UDP_PORT)
        for ($i = 0; $i -lt $Count; $i++) {
            try   { $udp.Send($payload, 512) | Out-Null; Start-Sleep -Milliseconds 20 }
            catch { $errs++ }
        }
        $udp.Close()
    } catch { $errs++ }
    return $errs
}

function Start-Replica {
    param([string]$Name, [string]$Cpus, [string]$Image)
    Log "Scale-UP horizontal : spawn $Name (CPU limit $Cpus)" "Magenta"
    $net = docker network ls --filter "name=tp" --format "{{.Name}}" | Select-Object -First 1
    if (-not $net) { $net = "bridge" }
    docker run -d --name $Name --network $net --cpus $Cpus --memory "256m" --stop-signal SIGTERM $Image | Out-Null
    Start-Sleep -Seconds 4
    $ok = Test-ContainerRunning $Name
    Log "Replica $Name demarre : $ok" $(if ($ok) { "Green" } else { "Red" })
    return $ok
}

function Stop-Replica {
    param([string]$Name)
    Log "Scale-DOWN : arret $Name (SIGTERM)" "Red"
    docker stop $Name 2>$null | Out-Null
    docker rm   $Name 2>$null | Out-Null
}

# ===================================================================
# EN-TETE DU RAPPORT
# ===================================================================

$script:Report.Add("# Rapport de Stress Test - TeamSpeak Docker Cloud")
$script:Report.Add("")
$script:Report.Add("> Genere le $((Get-Date).ToString('dd/MM/yyyy a HH:mm:ss'))")
$script:Report.Add("")
$script:Report.Add("## Architecture testee")
$script:Report.Add("| Replica | Container | CPU limit | Condition |")
$script:Report.Add("|---|---|---|---|")
$script:Report.Add("| R1 | $CONTAINER_R1 | $CPU_R1 | Container de base (compose) |")
$script:Report.Add("| R2 | $CONTAINER_R2 | $CPU_R2 | Spawne si CPU R1 > ${CPU_SCALE_UP}% |")
$script:Report.Add("| R3 | $CONTAINER_R3 | $CPU_R3 | Spawne si CPU R2 > ${CPU_SCALE_UP}% |")
$script:Report.Add("| Stop | R3 stoppe | - | Si CPU R3 > ${CPU_STOP}% |")
$script:Report.Add("")

# ===================================================================
# VERIFICATION PREREQUIS
# ===================================================================

LogSection "VERIFICATION PREREQUIS"

if (-not (Test-ContainerRunning $CONTAINER_R1)) {
    Log "ERREUR : $CONTAINER_R1 n'est pas demarre. Lance : docker compose up --build -d" "Red"
    exit 1
}
Log "Container $CONTAINER_R1 actif." "Green"

$hc = Invoke-Api "health"
if ($hc.Status -ne 200) {
    Log "ERREUR : /api/health retourne $($hc.Status). L'API n'est pas accessible." "Red"
    exit 1
}
Log "API Flask accessible : /api/health -> $($hc.Status) en $($hc.Ms)ms" "Green"

$imgRaw = docker images --format "{{.Repository}}:{{.Tag}}" 2>$null |
    Where-Object { $_ -match "webserver" } |
    Select-Object -First 1
$WEBSERVER_IMAGE = if ($imgRaw) { $imgRaw -replace ":.*", "" } else { $null }
if ($WEBSERVER_IMAGE) {
    Log "Image webserver detectee : $WEBSERVER_IMAGE" "Green"
} else {
    Log "Image webserver non trouvee - scaling desactive." "Yellow"
}

# ===================================================================
# PHASE 1 - REPLICA 1 (CPU 0.25) - TESTS TS3 DE BASE
# ===================================================================

LogSection "PHASE 1 - REPLICA 1 (CPU $CPU_R1) - Tests TS3 de base"
LogTableHeader

# T1.1 - Baseline /api/health x10
Log "T1.1 - Baseline /api/health x10 sequentiel"
$lats = @(); $errs = 0
1..10 | ForEach-Object {
    $r = Invoke-Api "health"
    if ($r.Status -eq 200) { $lats += $r.Ms } else { $errs++ }
}
$avgH = if ($lats.Count -gt 0) { [int]($lats | Measure-Object -Average).Average } else { 9999 }
$maxH = if ($lats.Count -gt 0) { ($lats | Measure-Object -Maximum).Maximum } else { 9999 }
LogResult "T1.1 /api/health x10" "avg=${avgH}ms | max=${maxH}ms | erreurs=$errs" ($errs -eq 0)

# T1.2 - ServerQuery serverinfo() via /api/stats
Log "T1.2 - ServerQuery serverinfo via /api/stats x10"
$lats = @(); $errs = 0
1..10 | ForEach-Object {
    $r = Invoke-Api "stats" -TimeoutSec 10
    if ($r.Status -eq 200) { $lats += $r.Ms } else { $errs++ }
    Start-Sleep -Milliseconds 200
}
$avgS = if ($lats.Count -gt 0) { [int]($lats | Measure-Object -Average).Average } else { 9999 }
$maxS = if ($lats.Count -gt 0) { ($lats | Measure-Object -Maximum).Maximum } else { 9999 }
LogResult "T1.2 /api/stats (serverinfo)" "avg=${avgS}ms | max=${maxS}ms | erreurs=$errs" ($errs -eq 0)

# T1.3 - ServerQuery channellist() via /api/channels
Log "T1.3 - ServerQuery channellist via /api/channels x10"
$lats = @(); $errs = 0
1..10 | ForEach-Object {
    $r = Invoke-Api "channels" -TimeoutSec 10
    if ($r.Status -eq 200) { $lats += $r.Ms } else { $errs++ }
    Start-Sleep -Milliseconds 200
}
$avgC = if ($lats.Count -gt 0) { [int]($lats | Measure-Object -Average).Average } else { 9999 }
LogResult "T1.3 /api/channels (channellist)" "avg=${avgC}ms | erreurs=$errs" ($errs -eq 0)

# T1.4 - ServerQuery N+1 clientinfo() via /api/users
Log "T1.4 - ServerQuery N+1 clientinfo via /api/users x10 sequentiel"
$lats = @(); $errs = 0
1..10 | ForEach-Object {
    $r = Invoke-Api "users" -TimeoutSec 15
    if ($r.Status -eq 200) { $lats += $r.Ms } else { $errs++ }
    Start-Sleep -Milliseconds 300
}
$avgU = if ($lats.Count -gt 0) { [int]($lats | Measure-Object -Average).Average } else { 9999 }
$maxU = if ($lats.Count -gt 0) { ($lats | Measure-Object -Maximum).Maximum } else { 9999 }
LogResult "T1.4 /api/users (N+1 ServerQuery)" "avg=${avgU}ms | max=${maxU}ms | erreurs=$errs" ($errs -eq 0)

# T1.5 - UDP voix TS3 leger (~1 client vocal)
$udpE1 = Send-UdpPackets -Count 25 -Phase "P1"
LogResult "T1.5 UDP port 9987 (voix TS3 - 1 client)" "25 paquets 512B | erreurs=$udpE1" ($udpE1 -eq 0)

# T1.6 - Snapshot CPU
Start-Sleep -Seconds 2
$cpu1 = Get-ContainerCpu $CONTAINER_R1
Log "T1.6 - CPU $CONTAINER_R1 apres Phase 1 : ${cpu1}%" $(if ($cpu1 -lt $CPU_SCALE_UP) { "Green" } else { "Yellow" })
$script:Report.Add("| INFO | T1.6 CPU Replica 1 | ${cpu1}% (seuil scale-up: ${CPU_SCALE_UP}%) |")

# ===================================================================
# DECISION : SPAWN REPLICA 2
# ===================================================================

LogSection "DECISION AUTO-SCALING -> REPLICA 2"

$r2Ok = $false
if ($cpu1 -ge $CPU_SCALE_UP) {
    Log "CPU R1 = ${cpu1}% >= ${CPU_SCALE_UP}% -> Scale-UP -> Spawn R2 (CPU $CPU_R2)" "Magenta"
    $script:Report.Add("**Decision** : CPU R1 = ${cpu1}% >= ${CPU_SCALE_UP}% -> Scale-UP -> Spawn R2")
} else {
    Log "CPU R1 = ${cpu1}% < ${CPU_SCALE_UP}% - Pas de scaling automatique." "Green"
    Log "Spawn R2 force pour le test de charge." "Yellow"
    $script:Report.Add("**Decision** : CPU R1 = ${cpu1}% < ${CPU_SCALE_UP}% - Spawn R2 force pour test.")
}
if ($WEBSERVER_IMAGE) {
    $r2Ok = Start-Replica -Name $CONTAINER_R2 -Cpus $CPU_R2 -Image $WEBSERVER_IMAGE
}

# ===================================================================
# PHASE 2 - REPLICA 2 (CPU 0.45) - STRESS MODERE
# ===================================================================

LogSection "PHASE 2 - REPLICA 2 (CPU $CPU_R2) - Stress ServerQuery modere"
LogTableHeader

# T2.1 - ServerQuery flooding : 10 appels /api/users en parallele
Log "T2.1 - ServerQuery flooding : 10 appels /api/users en parallele"
$p2 = Invoke-ParallelApi -Ep "users" -Count 10
LogResult "T2.1 /api/users x10 parallele (flood ServerQuery)" "avg=$($p2.Avg)ms | max=$($p2.Max)ms | OK=$($p2.Success)/10 | erreurs=$($p2.Errors)" ($p2.Errors -lt 3)

# T2.2 - Dashboard refresh x10
Log "T2.2 - Dashboard refresh x10 : stats + channels + users + logs"
$dErrs = 0; $dLats = @()
1..10 | ForEach-Object {
    foreach ($ep in @("stats","channels","users","logs")) {
        $r = Invoke-Api $ep -TimeoutSec 12
        if ($r.Status -eq 200) { $dLats += $r.Ms } else { $dErrs++ }
    }
    Start-Sleep -Milliseconds 100
}
$avgD = if ($dLats.Count -gt 0) { [int]($dLats | Measure-Object -Average).Average } else { 9999 }
LogResult "T2.2 Dashboard refresh x10 (40 appels TS3)" "avg=${avgD}ms | erreurs=$dErrs" ($dErrs -lt 5)

# T2.3 - UDP voix modere (~2 clients vocaux)
$udpE2 = Send-UdpPackets -Count 50 -Phase "P2"
LogResult "T2.3 UDP port 9987 (voix TS3 - 2 clients)" "50 paquets 512B | erreurs=$udpE2" ($udpE2 -eq 0)

# T2.4 - Snapshot CPU
Start-Sleep -Seconds 2
$targetR2 = if ($r2Ok) { $CONTAINER_R2 } else { $CONTAINER_R1 }
$cpu2 = Get-ContainerCpu $targetR2
Log "T2.4 - CPU $targetR2 apres Phase 2 : ${cpu2}%" $(if ($cpu2 -lt $CPU_SCALE_UP) { "Green" } else { "Yellow" })
$script:Report.Add("| INFO | T2.4 CPU Replica 2 | ${cpu2}% (seuil scale-up: ${CPU_SCALE_UP}%) |")

# ===================================================================
# DECISION : SPAWN REPLICA 3
# ===================================================================

LogSection "DECISION AUTO-SCALING -> REPLICA 3"

$r3Ok = $false
if ($cpu2 -ge $CPU_SCALE_UP) {
    Log "CPU R2 = ${cpu2}% >= ${CPU_SCALE_UP}% -> Scale-UP -> Spawn R3 (CPU $CPU_R3)" "Magenta"
    $script:Report.Add("**Decision** : CPU R2 = ${cpu2}% >= ${CPU_SCALE_UP}% -> Scale-UP -> Spawn R3")
} else {
    Log "CPU R2 = ${cpu2}% < ${CPU_SCALE_UP}% - Spawn R3 force pour saturation max." "Yellow"
    $script:Report.Add("**Decision** : CPU R2 = ${cpu2}% < ${CPU_SCALE_UP}% - Spawn R3 force.")
}
if ($WEBSERVER_IMAGE) {
    $r3Ok = Start-Replica -Name $CONTAINER_R3 -Cpus $CPU_R3 -Image $WEBSERVER_IMAGE
}

# ===================================================================
# PHASE 3 - REPLICA 3 (CPU 0.65) - STRESS MAX + MONITOR SATURATION
# ===================================================================

LogSection "PHASE 3 - REPLICA 3 (CPU $CPU_R3) - Stress max + monitor saturation"
LogTableHeader

# T3.1 - ServerQuery flooding intensif : 20 appels paralleles
Log "T3.1 - ServerQuery flooding intensif : 20 appels /api/users en parallele"
$p3 = Invoke-ParallelApi -Ep "users" -Count 20
LogResult "T3.1 /api/users x20 parallele (ServerQuery sature)" "avg=$($p3.Avg)ms | max=$($p3.Max)ms | OK=$($p3.Success)/20 | erreurs=$($p3.Errors)" ($p3.Success -gt 10)

# T3.2 - Dashboard rapide x20
Log "T3.2 - Dashboard refresh rapide x20 : stats + channels + users + logs"
$dErrs3 = 0; $dLats3 = @()
1..20 | ForEach-Object {
    foreach ($ep in @("stats","channels","users","logs")) {
        $r = Invoke-Api $ep -TimeoutSec 12
        if ($r.Status -eq 200) { $dLats3 += $r.Ms } else { $dErrs3++ }
    }
    Start-Sleep -Milliseconds 50
}
$avgD3 = if ($dLats3.Count -gt 0) { [int]($dLats3 | Measure-Object -Average).Average } else { 9999 }
LogResult "T3.2 Dashboard rapide x20 (80 appels TS3)" "avg=${avgD3}ms | erreurs=$dErrs3" ($dErrs3 -lt 10)

# T3.3 - UDP voix intensif (~8 clients vocaux)
$udpE3 = Send-UdpPackets -Count 200 -Phase "P3"
LogResult "T3.3 UDP port 9987 intensif (8 clients vocaux)" "200 paquets 512B | erreurs=$udpE3" ($udpE3 -eq 0)

# T3.4 - Monitor CPU continu + arret si > 80%
Log "T3.4 - Monitor CPU R3 toutes les ${MONITOR_SEC}s (10 lectures max)"
$targetR3 = if ($r3Ok) { $CONTAINER_R3 } else { $CONTAINER_R1 }
$stopped  = $false
$samples  = @()

for ($i = 1; $i -le 10; $i++) {
    $cpuNow = Get-ContainerCpu $targetR3
    $samples += $cpuNow
    $color = if ($cpuNow -ge $CPU_STOP) { "Red" } elseif ($cpuNow -ge 60) { "Yellow" } else { "Green" }
    Log "  Lecture $i/10 - CPU $targetR3 : ${cpuNow}%" $color

    if ($cpuNow -ge $CPU_STOP) {
        Log "SATURATION : CPU ${cpuNow}% >= ${CPU_STOP}% -> Scale-DOWN automatique de $targetR3" "Red"
        $script:Report.Add("| STOP | T3.4 SATURATION DETECTEE | CPU = ${cpuNow}% >= ${CPU_STOP}% -> Scale-DOWN |")
        if ($r3Ok) { Stop-Replica $CONTAINER_R3 }
        $stopped = $true
        break
    }
    Start-Sleep -Seconds $MONITOR_SEC
}

$cpu3Max = if ($samples.Count -gt 0) { ($samples | Measure-Object -Maximum).Maximum } else { -1 }
if (-not $stopped) {
    Log "CPU max R3 : ${cpu3Max}% - Seuil ${CPU_STOP}% non atteint." "Green"
    $script:Report.Add("| OK | T3.4 Monitor CPU R3 | CPU max = ${cpu3Max}% - Seuil ${CPU_STOP}% non atteint |")
}

# ===================================================================
# NETTOYAGE
# ===================================================================

LogSection "NETTOYAGE"
if ($r3Ok -and -not $stopped) { Stop-Replica $CONTAINER_R3 }
if ($r2Ok)                    { Stop-Replica $CONTAINER_R2 }
Log "Nettoyage termine. Seul $CONTAINER_R1 reste actif." "Green"

# ===================================================================
# RAPPORT FINAL
# ===================================================================

$duration = [int]((Get-Date) - $script:StartTime).TotalSeconds

$script:Report.Add("")
$script:Report.Add("---")
$script:Report.Add("## Resume")
$script:Report.Add("")
$script:Report.Add("| Replica | CPU limit | CPU max mesure | Saturation |")
$script:Report.Add("|---|---|---|---|")
$script:Report.Add("| R1 ($CONTAINER_R1) | $CPU_R1 | ${cpu1}% | $(if ($cpu1 -ge $CPU_SCALE_UP) {"Oui (> ${CPU_SCALE_UP}%)"} else {"Non"}) |")
$script:Report.Add("| R2 ($CONTAINER_R2) | $CPU_R2 | ${cpu2}% | $(if ($cpu2 -ge $CPU_SCALE_UP) {"Oui (> ${CPU_SCALE_UP}%)"} else {"Non"}) |")
$script:Report.Add("| R3 ($CONTAINER_R3) | $CPU_R3 | ${cpu3Max}% | $(if ($stopped) {"Oui - arret automatique"} else {"Non"}) |")
$script:Report.Add("")
$script:Report.Add("**Duree totale :** ${duration}s")
$script:Report.Add("")
$script:Report.Add("### Vecteurs de saturation testes (TeamSpeak uniquement)")
$script:Report.Add("- **ServerQuery TCP port 10011** : flood /api/users (N+1 clientinfo)")
$script:Report.Add("- **Dashboard refresh** : stats + channels + users + logs")
$script:Report.Add("- **UDP voix port 9987** : simulation clients vocaux codec OPUS")
$script:Report.Add("")
$script:Report.Add("### Auto-scaling horizontal")
$script:Report.Add("- Spawn de nouveaux containers si CPU > ${CPU_SCALE_UP}%")
$script:Report.Add("- Stop automatique replica 3 si CPU > ${CPU_STOP}%")

$script:Report | Out-File -FilePath $REPORT_PATH -Encoding UTF8
LogSection "TERMINE"
Log "Tests termines en ${duration}s. Rapport : $REPORT_PATH" "Cyan"
