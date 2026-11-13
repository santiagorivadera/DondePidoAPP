param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$expected = @('frontend_uiux', 'backend_supabase', 'database_postgresql', 'qa_security', 'devops_deployment', 'documentation_architecture')
Push-Location $projectRoot
try {
    $config = Get-Content -LiteralPath '.codex/config.toml' -Raw
    if ($config -notmatch '(?m)^max_concurrent_threads_per_session\s*=\s*3\s*$') {
        throw 'El límite configurado debe ser 3 subagentes.'
    }
    $startup = & codex --strict-config app-server --print-startup-config
    if ($LASTEXITCODE -ne 0) { throw 'Codex rechazó la configuración.' }
    $null = ($startup -join "`n") | ConvertFrom-Json
    $prompt = & codex debug prompt-input 'Verificación local de catálogo, sin ejecutar tareas.'
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo construir el contexto de Codex.' }
    $promptText = $prompt -join "`n"
    $null = $promptText | ConvertFrom-Json
    $files = @(Get-ChildItem -LiteralPath '.codex/agents' -Filter '*.toml')
    if ($files.Count -ne 6) { throw 'Se esperaban exactamente seis perfiles TOML.' }
    $catalogOutput = & codex debug models
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el catálogo de modelos.' }
    $catalog = ($catalogOutput -join "`n") | ConvertFrom-Json
    function Assert-ModelPair([string]$text, [string]$label, [string]$modelKey, [string]$effortKey) {
        $modelMatch = [regex]::Match($text, "(?m)^$modelKey\s*=\s*`"([^`"]+)`"")
        $effortMatch = [regex]::Match($text, "(?m)^$effortKey\s*=\s*`"([^`"]+)`"")
        if (-not $modelMatch.Success -or -not $effortMatch.Success) { throw "Falta modelo/esfuerzo en $label" }
        $modelName = $modelMatch.Groups[1].Value
        $effort = $effortMatch.Groups[1].Value
        $modelInfo = @($catalog.models | Where-Object { $_.slug -eq $modelName })
        if ($modelInfo.Count -ne 1) { throw "Modelo no encontrado: $modelName" }
        if ($effort -notin $modelInfo[0].supported_reasoning_levels.effort) { throw "Esfuerzo no compatible: $label $effort" }
        Write-Output "OK modelo: $label = $modelName / $effort"
    }
    Assert-ModelPair $config 'Tech Lead' 'model' 'model_reasoning_effort'
    Assert-ModelPair $config 'Subagente genérico' 'default_subagent_model' 'default_subagent_reasoning_effort'
    foreach ($name in $expected) {
        $profile = Get-Content -LiteralPath ".codex/agents/$name.toml" -Raw
        foreach ($field in @('name', 'description', 'developer_instructions')) {
            if ($profile -notmatch "(?m)^$field\s*=") { throw "Falta $field en $name" }
        }
        # El formato nombre: { corresponde al catálogo, no a la tabla de AGENTS.md.
        if (-not $promptText.Contains("${name}: {")) { throw "Codex no reconoce $name en su catálogo." }
        Assert-ModelPair $profile $name 'model' 'model_reasoning_effort'
        Write-Output "OK catálogo: $name"
    }
    if (-not $promptText.Contains('DondePido — instrucciones del equipo')) {
        throw 'Codex no cargó las instrucciones del proyecto.'
    }
    Write-Output 'OK: configuración estricta, seis especialistas, AGENTS.md y límite configurado=3.'
    Write-Output 'Esta verificación no ejecuta inferencia ni mide ahorro, aislamiento o despliegues.'
} finally {
    Pop-Location
}
