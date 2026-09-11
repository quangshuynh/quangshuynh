param(
    [switch]$Apply,
    [switch]$IncludePrivate,
    [switch]$IncludeArchived,
    [switch]$IncludeForks,
    [int]$MaxTopics = 8
)

$Owner = "quangshuynh"

# -----------------------------
# Basic checks
# -----------------------------

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH."
    exit 1
}

gh auth status *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI is not authenticated. Run: gh auth login"
    exit 1
}

Write-Host ""
Write-Host "GitHub Topic Manager" -ForegroundColor Cyan
Write-Host "Owner: $Owner"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'DRY RUN' })"
Write-Host ""

# -----------------------------
# Helpers
# -----------------------------

function Add-Topic {
    param(
        [System.Collections.Generic.HashSet[string]]$Set,
        [string]$Topic
    )

    if ([string]::IsNullOrWhiteSpace($Topic)) {
        return
    }

    $normalized = $Topic.ToLowerInvariant().Trim()
    $normalized = $normalized -replace '[^a-z0-9\-]', '-'
    $normalized = $normalized -replace '-+', '-'
    $normalized = $normalized.Trim('-')

    if ($normalized.Length -gt 0 -and $normalized.Length -le 50) {
        [void]$Set.Add($normalized)
    }
}

function Get-RepoTopics {
    param([string]$FullName)

    $json = & gh api `
        -H "Accept: application/vnd.github+json" `
        "repos/$FullName/topics" 2>$null

    if ($LASTEXITCODE -ne 0) {
        return [PSCustomObject]@{
            Success = $false
            Topics  = @()
        }
    }

    try {
        $obj = $json | ConvertFrom-Json

        return [PSCustomObject]@{
            Success = $true
            Topics  = @($obj.names)
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Topics  = @()
        }
    }
}

function Get-RepoReadme {
    param([string]$FullName)

    $json = gh api `
        -H "Accept: application/vnd.github+json" `
        "repos/$FullName/readme" 2>$null

    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    try {
        $obj = $json | ConvertFrom-Json

        if (-not $obj.content) {
            return ""
        }

        $encoded = $obj.content -replace '\s', ''
        $bytes = [Convert]::FromBase64String($encoded)
        return [Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        return ""
    }
}

function Get-RepoLanguages {
    param([string]$FullName)

    $json = gh api `
        -H "Accept: application/vnd.github+json" `
        "repos/$FullName/languages" 2>$null

    if ($LASTEXITCODE -ne 0) {
        return @()
    }

    try {
        $obj = $json | ConvertFrom-Json
        return @($obj.PSObject.Properties.Name)
    }
    catch {
        return @()
    }
}

function Get-SuggestedTopics {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Readme,
        [string[]]$Languages
    )

    # Ordered list so high-confidence topics stay ahead of generic ones.
    $topics = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    function Add-PrioritizedTopic {
        param([string]$Topic)

        if ([string]::IsNullOrWhiteSpace($Topic)) {
            return
        }

        $normalized = $Topic.ToLowerInvariant().Trim()
        $normalized = $normalized -replace '[^a-z0-9\-]', '-'
        $normalized = $normalized -replace '-+', '-'
        $normalized = $normalized.Trim('-')

        if (
            $normalized.Length -gt 0 -and
            $normalized.Length -le 50 -and
            $seen.Add($normalized)
        ) {
            $topics.Add($normalized)
        }
    }

    $nameLower = $Name.ToLowerInvariant()
    $combined = "$Name $Description $Readme".ToLowerInvariant()

    # ---------------------------------------------------------
    # 1. Repo-specific / domain-specific high-confidence topics
    # ---------------------------------------------------------

    switch -Regex ($nameLower) {
        '^dashpilot$' {
            @(
                'delivery-tracker',
                'mileage-tracker',
                'ios',
                'swift',
                'swiftui',
                'swiftdata',
                'corelocation',
                'local-first'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^casenotes$' {
            @(
                'notes-app',
                'ios',
                'swift',
                'swiftui',
                'swiftdata',
                'pencilkit',
                'markdown',
                'local-first'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^promptcue$' {
            @(
                'ai-assistant',
                'macos',
                'swift',
                'swiftui',
                'local-llm',
                'speech-recognition',
                'transcription',
                'local-first'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^scribekit$' {
            @(
                'transcription',
                'meeting-notes',
                'macos',
                'swift',
                'swiftui',
                'screencapturekit',
                'speech-recognition',
                'local-first'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^gitprofilelens$' {
            @(
                'github',
                'github-api',
                'repository-analysis',
                'repository-audit',
                'developer-tools',
                'portfolio'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^585dashcam585$' {
            @(
                'dashcam',
                'ecommerce',
                'react',
                'vite',
                'supabase',
                'stripe',
                'cloudflare-workers',
                'javascript'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^585photo585$' {
            @(
                'photography',
                'photo-gallery',
                'portfolio',
                'react',
                'vite',
                'javascript'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^business-data-automation$' {
            @(
                'data-pipeline',
                'data-validation',
                'financial-reconciliation',
                'etl',
                'fastapi',
                'postgresql',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^used-car-price-ml$|^car-prices-prediction$' {
            @(
                'machine-learning',
                'car-price-prediction',
                'regression',
                'data-science',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^photo-archive$' {
            @(
                'photography',
                'photo-archive',
                'digital-photography'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^emonics-ios-training$' {
            @(
                'ios',
                'swift',
                'swift-training'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^minecraft-optimized-start-batch$' {
            @(
                'minecraft',
                'automation',
                'batch-script'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^minecraft-server-' {
            @(
                'minecraft',
                'minecraft-server'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^minecraft-summer-' {
            @(
                'minecraft',
                'minecraft-server'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^text-based-minecraft$' {
            @(
                'text-game',
                'minecraft',
                'game'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^chess\.com-stockfish$' {
            @(
                'chess',
                'stockfish',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^weather-app$' {
            @(
                'weather',
                'web-app',
                'api'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^angular-tour-of-heroes$' {
            @(
                'angular',
                'typescript',
                'tutorial'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^javafx-board-game$' {
            @(
                'javafx',
                'java',
                'game'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^wpf-learning$' {
            @(
                'wpf',
                'dotnet',
                'csharp'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^bulk-md-to-pdf$' {
            @(
                'markdown-to-pdf',
                'pdf',
                'markdown',
                'automation',
                'cli'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^pdf-merger$' {
            @(
                'pdf-merger',
                'pdf',
                'automation',
                'cli'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        'craigslist-scraper|facebook-markteplace-web-scrapper' {
            @(
                'web-scraping',
                'automation',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^personalized-budgeting-assistant$|^banked$' {
            @(
                'personal-finance',
                'budgeting',
                'finance'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^githubio-old$|^quang-personal-website$|^quanghuynh-website$' {
            @(
                'personal-website',
                'portfolio',
                'web-development'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^full-stack-e-commerce-website$' {
            @(
                'ecommerce',
                'full-stack',
                'web-development'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^python-desktop-cleaner$' {
            @(
                'desktop-cleaner',
                'automation',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^tuned$' {
            @(
                'music-app',
                'music'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^passwordmanager$' {
            @(
                'password-manager',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^russian-roulette$' {
            @(
                'cli',
                'game',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^tic-tac-toe$' {
            @(
                'tic-tac-toe',
                'game',
                'java'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^magic-8-ball$' {
            @(
                'magic-8-ball',
                'game'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^coin-flip-simulator$' {
            @(
                'simulation',
                'game'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^even-or-odd$' {
            Add-PrioritizedTopic 'cpp'
        }

        '^calculatorhw$' {
            Add-PrioritizedTopic 'java'
        }

        '^csci141$' {
            @(
                'computer-science',
                'python'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^csci142$' {
            @(
                'computer-science',
                'java'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }

        '^csci243$' {
            @(
                'computer-science',
                'systems-programming'
            ) | ForEach-Object { Add-PrioritizedTopic $_ }
        }
    }

    # ---------------------------------------------------------
    # 2. Framework / domain topics inferred from actual content
    # ---------------------------------------------------------

    $keywordRules = @(
        @{ Pattern = '\bswiftui\b'; Topic = 'swiftui' },
        @{ Pattern = '\bswiftdata\b'; Topic = 'swiftdata' },
        @{ Pattern = '\bios\b'; Topic = 'ios' },
        @{ Pattern = '\bmacos\b'; Topic = 'macos' },
        @{ Pattern = '\bcorelocation\b'; Topic = 'corelocation' },
        @{ Pattern = '\bpencilkit\b'; Topic = 'pencilkit' },
        @{ Pattern = '\blocalauthentication\b'; Topic = 'localauthentication' },
        @{ Pattern = '\bscreencapturekit\b'; Topic = 'screencapturekit' },
        @{ Pattern = '\bspeech recognition\b|\bspeech-recognition\b'; Topic = 'speech-recognition' },

        @{ Pattern = '\breact\b'; Topic = 'react' },
        @{ Pattern = '\bvite\b'; Topic = 'vite' },
        @{ Pattern = '\bnext\.?js\b'; Topic = 'nextjs' },
        @{ Pattern = '\bangular\b'; Topic = 'angular' },
        @{ Pattern = '\bnode\.?js\b'; Topic = 'nodejs' },
        @{ Pattern = '\bfastapi\b'; Topic = 'fastapi' },
        @{ Pattern = '\bflask\b'; Topic = 'flask' },
        @{ Pattern = '\bdjango\b'; Topic = 'django' },

        @{ Pattern = '\bsupabase\b'; Topic = 'supabase' },
        @{ Pattern = '\bpostgres(?:ql)?\b'; Topic = 'postgresql' },
        @{ Pattern = '\balembic\b'; Topic = 'alembic' },
        @{ Pattern = '\bstripe\b'; Topic = 'stripe' },
        @{ Pattern = '\bcloudflare\b'; Topic = 'cloudflare-workers' },
        @{ Pattern = '\bvercel\b'; Topic = 'vercel' },

        @{ Pattern = '\bmachine learning\b|\bmachine-learning\b'; Topic = 'machine-learning' },
        @{ Pattern = '\bdeep learning\b|\bdeep-learning\b'; Topic = 'deep-learning' },
        @{ Pattern = '\bartificial intelligence\b|\bai\b'; Topic = 'artificial-intelligence' },
        @{ Pattern = '\bopenai\b'; Topic = 'openai' },
        @{ Pattern = '\bllm\b|\blanguage model\b'; Topic = 'llm' },
        @{ Pattern = '\bcomputer vision\b|\bcomputer-vision\b'; Topic = 'computer-vision' },
        @{ Pattern = '\bocr\b'; Topic = 'ocr' },
        @{ Pattern = '\bdata science\b|\bdata-science\b'; Topic = 'data-science' },
        @{ Pattern = '\bdata analysis\b|\bdata-analysis\b'; Topic = 'data-analysis' },
        @{ Pattern = '\bdata pipeline\b|\bdata-pipeline\b|\betl\b'; Topic = 'data-pipeline' },

        @{ Pattern = '\bweb scraping\b|\bweb-scraping\b|\bscraper\b'; Topic = 'web-scraping' },
        @{ Pattern = '\brest api\b|\brest-api\b'; Topic = 'rest-api' },
        @{ Pattern = '\bautomation\b'; Topic = 'automation' },
        @{ Pattern = '\bdesktop app\b|\bdesktop-app\b'; Topic = 'desktop-app' },
        @{ Pattern = '\bwpf\b'; Topic = 'wpf' },
        @{ Pattern = '\bjavafx\b'; Topic = 'javafx' },
        @{ Pattern = '\bportfolio\b'; Topic = 'portfolio' },
        @{ Pattern = '\bphotograph(?:y|ic)\b'; Topic = 'photography' },
        @{ Pattern = '\bphoto archive\b|\bphoto-archive\b'; Topic = 'photo-archive' },
        @{ Pattern = '\be-?commerce\b'; Topic = 'ecommerce' },
        @{ Pattern = '\bbudget(?:ing)?\b|\bpersonal finance\b'; Topic = 'budgeting' },
        @{ Pattern = '\bweather\b'; Topic = 'weather' },
        @{ Pattern = '\bchess\b'; Topic = 'chess' },
        @{ Pattern = '\bstockfish\b'; Topic = 'stockfish' },
        @{ Pattern = '\bminecraft\b'; Topic = 'minecraft' },
        @{ Pattern = '\bmarkdown\b'; Topic = 'markdown' },
        @{ Pattern = '\bmusic\b'; Topic = 'music' },
        @{ Pattern = '\bcooking\b|\brecipe\b'; Topic = 'cooking' },
        @{ Pattern = '\btranscrib'; Topic = 'transcription' },
        @{ Pattern = '\blocal[- ]first\b'; Topic = 'local-first' }
    )

    foreach ($rule in $keywordRules) {
        if ($combined -match $rule.Pattern) {
            Add-PrioritizedTopic $rule.Topic
        }
    }

    # ---------------------------------------------------------
    # 3. Languages
    # ---------------------------------------------------------

    foreach ($language in $Languages) {
        switch ($language.ToLowerInvariant()) {
            "swift"      { Add-PrioritizedTopic "swift" }
            "python"     { Add-PrioritizedTopic "python" }
            "javascript" { Add-PrioritizedTopic "javascript" }
            "typescript" { Add-PrioritizedTopic "typescript" }
            "java"       { Add-PrioritizedTopic "java" }
            "kotlin"     { Add-PrioritizedTopic "kotlin" }
            "c#"         { Add-PrioritizedTopic "csharp" }
            "c++"        { Add-PrioritizedTopic "cpp" }
            "go"         { Add-PrioritizedTopic "golang" }
            "rust"       { Add-PrioritizedTopic "rust" }
            "powershell" { Add-PrioritizedTopic "powershell" }
            "shell"      { Add-PrioritizedTopic "shell" }
        }
    }

    # ---------------------------------------------------------
    # 4. Low-priority generic topics
    # Only add these after meaningful/domain topics.
    # ---------------------------------------------------------

    $genericRules = @(
        @{ Pattern = '\bapi\b'; Topic = 'api' },
        @{ Pattern = '\bcli\b|\bcommand line\b'; Topic = 'cli' },
        @{ Pattern = '\bgithub\b'; Topic = 'github' },
        @{ Pattern = '\bgit\b'; Topic = 'git' }
    )

    foreach ($rule in $genericRules) {
        if ($combined -match $rule.Pattern) {
            Add-PrioritizedTopic $rule.Topic
        }
    }

    # Generic HTML/CSS are intentionally last.
    foreach ($language in $Languages) {
        switch ($language.ToLowerInvariant()) {
            "html" { Add-PrioritizedTopic "html" }
            "css"  { Add-PrioritizedTopic "css" }
        }
    }

    return @($topics | Select-Object -First $MaxTopics)
}

# -----------------------------
# Get ALL owned repositories
# -----------------------------

Write-Host "Retrieving repositories..." -ForegroundColor DarkGray

$repoLines = @(
    gh repo list $Owner `
        --limit 1000 `
        --json name,nameWithOwner,description,isPrivate,isArchived,isFork `
        --jq '.[] | @base64'
)

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to retrieve repositories."
    exit 1
}

$repos = @()

foreach ($line in $repoLines) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        continue
    }

    try {
        $bytes = [Convert]::FromBase64String($line.Trim())
        $json = [Text.Encoding]::UTF8.GetString($bytes)
        $repo = $json | ConvertFrom-Json

        $repos += $repo
    }
    catch {
        Write-Warning "Failed to parse a repository entry."
    }
}

if ($repos.Count -eq 0) {
    Write-Error "No repositories were returned by GitHub."
    exit 1
}

$reposAll = @($repos)

Write-Host "Found $($repos.Count) owned repositories." -ForegroundColor Green

# -----------------------------
# Filter
# -----------------------------

$repos = @(
    $repos | Where-Object {
        if (-not $IncludePrivate -and $_.isPrivate) {
            return $false
        }

        if (-not $IncludeArchived -and $_.isArchived) {
            return $false
        }

        if (-not $IncludeForks -and $_.isFork) {
            return $false
        }

        return $true
    }
)

Write-Host "Processing $($repos.Count) repositories after filters."
Write-Host ""

# -----------------------------
# Analyze
# -----------------------------

$results = @()

$updated = 0
$failed = 0
$skippedExisting = 0
$skippedNoSuggestion = 0

foreach ($repo in $repos) {
    $fullName = $repo.nameWithOwner

    Write-Host "Checking $fullName..." -ForegroundColor DarkGray

	$topicResult = Get-RepoTopics $fullName

	if (-not $topicResult.Success) {
		Write-Warning "Could not read topics for $fullName"
		$failed++

		$results += [PSCustomObject]@{
			Repository = $fullName
			Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
			Status     = "topic-read-failed"
			Topics     = ""
		}

		continue
	}

	$existingTopics = @($topicResult.Topics)

	if ($existingTopics.Count -gt 0) {
		$skippedExisting++

		$results += [PSCustomObject]@{
			Repository = $fullName
			Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
			Status     = "already-has-topics"
			Topics     = ($existingTopics -join ", ")
		}

		continue
	}

    $readme = Get-RepoReadme $fullName
    $languages = Get-RepoLanguages $fullName

    $suggestedTopics = Get-SuggestedTopics `
        -Name $repo.name `
        -Description $repo.description `
        -Readme $readme `
        -Languages $languages
		
	# Don't update a repo when all we know is its language/tooling.
	$weakOnlyTopics = @(
		'python',
		'java',
		'javascript',
		'typescript',
		'swift',
		'csharp',
		'cpp',
		'golang',
		'rust',
		'kotlin',
		'powershell',
		'shell',
		'html',
		'css',
		'git',
		'github',
		'api',
		'cli'
	)

	$meaningfulTopics = @(
		$suggestedTopics | Where-Object {
			$_ -notin $weakOnlyTopics
		}
	)

	if ($meaningfulTopics.Count -eq 0) {
		$suggestedTopics = @()
	}

    if (@($suggestedTopics).Count -eq 0) {
        $skippedNoSuggestion++

        $results += [PSCustomObject]@{
            Repository = $fullName
            Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
            Status     = "no-suggestion"
            Topics     = ""
        }

        continue
    }

    if (-not $Apply) {
        $results += [PSCustomObject]@{
            Repository = $fullName
            Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
            Status     = "would-update"
            Topics     = ($suggestedTopics -join ", ")
        }

        continue
    }

    $body = @{
        names = @($suggestedTopics)
    } | ConvertTo-Json -Compress

    $body | gh api `
        --method PUT `
        -H "Accept: application/vnd.github+json" `
        "repos/$fullName/topics" `
        --input - *> $null

    if ($LASTEXITCODE -eq 0) {
        $updated++

        $results += [PSCustomObject]@{
            Repository = $fullName
            Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
            Status     = "updated"
            Topics     = ($suggestedTopics -join ", ")
        }
    }
    else {
        $failed++

        $results += [PSCustomObject]@{
            Repository = $fullName
            Visibility = $(if ($repo.isPrivate) { "private" } else { "public" })
            Status     = "update-failed"
            Topics     = ($suggestedTopics -join ", ")
        }
    }
}

# -----------------------------
# Results
# -----------------------------

Write-Host ""
Write-Host "Results" -ForegroundColor Cyan
Write-Host "-------"

if ($results.Count -gt 0) {
    $results |
        Sort-Object Status, Repository |
        Format-Table Repository, Visibility, Status, Topics -AutoSize -Wrap
}
else {
    Write-Host "No results were recorded." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------"
Write-Host "Owned repos detected:     $($reposAll.Count)"
Write-Host "Repos processed:          $($repos.Count)"
Write-Host "Already had topics:       $skippedExisting"
Write-Host "No topic suggestion:      $skippedNoSuggestion"
Write-Host "Would update:             $( @($results | Where-Object Status -eq 'would-update').Count )"
Write-Host "Updated:                  $updated"
Write-Host "Failures:                 $failed"

if (-not $Apply) {
    Write-Host ""
    Write-Host "Dry run only. No GitHub topics were changed." -ForegroundColor Yellow
    Write-Host "Run again with -Apply when the suggestions look good."
}
