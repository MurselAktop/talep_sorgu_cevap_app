# Supabase'in ürettiği OpenAPI şemasını apikey header'ı ile indirir ve
# swagger/openapi.json olarak kaydeder. Swagger UI bu dosyayı canlı
# localhost:8000 adresi yerine yerel dosyadan okuyacak (bkz. docker-compose-swagger.yml).
#
# Neden gerekli: Swagger UI, şemayı ilk çekerken özel bir HTTP header
# (apikey) ekleyemiyor; Supabase ise apikey olmadan 401 döndürüyor.
# Bu yüzden şema önce apikey ile burada indirilip yerel dosya olarak sunuluyor.
#
# Kullanım: Supabase'i (localhost:8000) ayağa kaldırdıktan sonra çalıştır,
# ardından: docker compose -f docker-compose-swagger.yml up -d --force-recreate

$envFile = Join-Path $PSScriptRoot ".env"
$envVars = @{}
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)\s*=\s*(.*)\s*$') {
        $envVars[$matches[1].Trim()] = $matches[2].Trim()
    }
}

$supabaseUrl = $envVars["SUPABASE_URL"]
$anonKey = $envVars["SUPABASE_ANON_KEY"]

if (-not $supabaseUrl -or -not $anonKey) {
    Write-Error ".env dosyasinda SUPABASE_URL veya SUPABASE_ANON_KEY bulunamadi."
    exit 1
}

$restPath = "/rest/v1"

$outDir = Join-Path $PSScriptRoot "swagger"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir "openapi.json"

Invoke-RestMethod -Uri "$supabaseUrl$restPath/" -Headers @{ apikey = $anonKey } -OutFile $outFile

# PostgREST, Kong'un (Supabase gateway) arkasinda oldugunu bilmedigi icin
# semaya kendi ic container adresini (orn. host=0.0.0.0:3000, basePath=/)
# yazar. Bu adresler disaridan erisilemez; Swagger UI'in gercekten calisan
# host:port ve /rest/v1 on-ekiyle istek atmasi icin bu alanlari duzeltiyoruz.
$content = Get-Content -Path $outFile -Raw
$hostValue = $supabaseUrl -replace '^https?://', ''
$content = $content -replace '"host":"[^"]*"', ('"host":"' + $hostValue + '"')
$content = $content -replace '"basePath":"[^"]*"', ('"basePath":"' + $restPath + '"')
[System.IO.File]::WriteAllText($outFile, $content, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "OpenAPI semasi indirildi ve host/basePath duzeltildi: $outFile"
